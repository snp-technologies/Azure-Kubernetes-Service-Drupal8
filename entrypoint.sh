#!/bin/bash

service ssh start
service rsyslog start

/usr/sbin/apache2ctl -D FOREGROUND

mkdir /var/lock/apache2
mkdir /var/run/apache2
