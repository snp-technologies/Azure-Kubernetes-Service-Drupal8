FROM php:7.3-apache-stretch

ARG GIT_TOKEN
ARG BRANCH
ARG GIT_REPO

COPY apache2.conf /etc/apache2
COPY entrypoint.sh /bin/

RUN chmod 775 /bin/entrypoint.sh

# install the PHP extensions we need
RUN set -eux; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libfreetype6-dev \
		libjpeg-dev \
		libpng-dev \
		libpq-dev \
		libzip-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype-dir=/usr \
		--with-jpeg-dir=/usr \
		--with-png-dir=/usr \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# Additional libraries not in base recommendations
RUN apt-get update; \
	apt-get install -y --no-install-recommends \
        openssh-server \
        curl \
        git \
        mysql-client \
        nano \
        rsyslog \
        sudo \
        tcptraceroute \
        vim \
        wget \
        libssl-dev \
	;

# set php.ini file
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

# set recommended PHP.ini settings
# Include PHP recommendations from https://www.drupal.org/docs/7/system-requirements/php
RUN { \
  echo 'error_log=/var/log/apache2/php-error.log'; \
  echo 'log_errors=On'; \
  echo 'display_errors=Off'; \
  } >> /usr/local/etc/php/php.ini

# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# see https://www.drupal.org/docs/8/core/modules/syslog/overview#s-2-configure-syslog-to-log-to-a-separate-file-optional
RUN echo "local0.* /var/log/apache2/drupal.log" >> /etc/rsyslog.conf

# Install memcached support for php
RUN apt-get update && apt-get install -y libmemcached-dev zlib1g-dev \
    && pecl install memcached-3.1.3 \
    && docker-php-ext-enable memcached
RUN apt-get update && apt-get install -y memcached

### Begin Drush install ###
RUN wget https://github.com/drush-ops/drush/releases/download/8.1.13/drush.phar
RUN chmod +x drush.phar
RUN mv drush.phar /usr/local/bin/drush
RUN drush init -y
### END Drush install ###

#copy drupal code
WORKDIR /var/www/html
COPY . /var/www/html
#Alternatively you can clone from a remote repository
#RUN git clone -b $BRANCH https://$GIT_TOKEN@github.com/$GIT_REPO.git .

RUN mkdir -p /var/www/html/docroot/sites/default/files
RUN mkdir -p /var/www/html/config
RUN useradd --shell /bin/bash d8admin
RUN chown -R d8admin:www-data ./docroot;
RUN find . -type d -exec chmod u=rwx,g=rx,o= '{}' \;
RUN find . -type f -exec chmod u=rw,g=r,o= '{}' \;

ENTRYPOINT ["/bin/entrypoint.sh"]
