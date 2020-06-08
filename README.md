# Azure-Kubernetes-Service-Drupal8
A solution for running Drupal 8 workloads on Azure Kubernetes Service (AKS).

<!-- TOC -->

- [Azure-Kubernetes-Service-Drupal8](#azure-kubernetes-service-drupal8)
  - [Prerequisites](#prerequisites)
  - [Overview](#overview)
  - [Bring your own code](#bring-your-own-code)
  - [Bring your own database](#bring-your-own-database)
  - [Persistent Files](#persistent-files)
  - [Implementation](#implementation)
    - [Step 1 - Build and push your Docker image](#step-1---build-and-push-your-docker-image)
    - [Step 2 - Deploy to AKS](#step-2---deploy-to-aks)
    - [Step 3 - Validate the deployment](#step-3---validate-the-deployment)
  - [References](#references)

<!-- /TOC -->

<a id="prerequisites"></a>
## Prerequisites
* [AKS cluster](https://docs.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-cluster)
* [Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-get-started-azure-cli) or registry of your choice
* [Azure Database for MySQL](https://docs.microsoft.com/en-us/azure/mysql/quickstart-create-mysql-server-database-using-azure-portal) or other MySQL or Maria DB resource
* [Azure Storage account and the file shares](https://docs.microsoft.com/en-us/azure/aks/azure-files-volume)

<a id="overview"></a>
## Overview

For organizations embracing DevOps practices, common strategies in use today are: 

- Containerization with Docker
- Container orchestration with Kubernetes
- Leveraging the PaaS (platform-as-a-service) resources of a cloud provider

This repository illustrates how to apply these strategies to deploy a Drupal 8 container image in Azure Kubernetes Service (AKS) - Microsoft's PaaS for Kubernetes orchestration of Docker containers.

When combined with Azure Database for MySQL or MariaDB, organizations benefit from the low-maintenance, performant and highly available  managed services of Microsoft Azure for their Drupal content management system website.

This solution includes:

- A Docker solution to containerize your Drupal 8 application
- Kubernetes manifests with declarative instructions to deploy the container image to AKS

Needless to say, Drupal containerization and Kubernetes orchestration are a craft and there are many opinions on how to do it. We expect that users of this solution will customize it to varying degrees to match their application requirements. For instance, in the Dockerfile we include:

- Many PHP extensions common for Drupal 8 use cases, but you may need to add one or more (or choose to remove ones that you do not need).
- Deployments of the Drush CLI for Drupal and RSYSLOG to support the Drupal Syslog module. You may prefer to run these processes in separate containers.

Feel free to borrow, fork, experiment, raise issues and even submit a pull request!

> **Please Note**
> 
> By itself this solution is not intended for production workloads. Considerations such as AKS RBAC, networking, and pod scaling are not taken up here. Please review the [Azure Kubernetes Documentation](https://docs.microsoft.com/en-us/azure/aks/intro-kubernetes) for best practices to build and manage applications on Azure Kubernetes Service (AKS).
>
> **What about other Drupal versions?**
>   
> We specifically had Drupal 8 in mind for this solution. Feel free to fork and modify it to support Drupal 9 or 7.
>
> **What about other PHP based CMS platforms?**
>
>While Drupal is the use case for this repository, the concepts illustrated here are common to other CMS frameworks based on PHP, such as WordPress and Joomla. With refactoring, the techniques used in this solution can be applied to other frameworks.

<a id="byo-code"></a>
## Bring your own code

In the Dockerfile, there is a placeholder for your code:
```
RUN git clone -b $BRANCH https://$GIT_TOKEN@github.com/$GIT_REPO.git .
```
Note the use of build args for $BRANCH, $GIT_TOKEN, and $GIT_REPO.

Alternatively, you can use the Docker COPY command to copy code from your local disk into the image or clone from a different Git platform such as Azure Repos or Bitbucket.

Our recommendation is to place your code in a directory directly off the root of the repository. In this repository we provide a `/docroot` directory into which you can place your application code. In the Dockerfile, it is assumed that the application code is in the `/docroot` directory. Feel free, of course, to rename the directory with your preferred naming convention.

> :warning: If you use a different directory as your document root, remember to change the `DocumentRoot` value in `apache2.conf`.

<a id="byo-database"></a>
## Bring your own database

MySQL (or other Drupal compatible database) is not included in the Dockerfile. In Azure, it is recommended that you run an instance of [Azure Database for MySQL](https://docs.microsoft.com/en-us/azure/mysql/) or [MariaDB](https://docs.microsoft.com/en-us/azure/Mariadb/) in the same region as your AKS cluster.

The Kubernetes Secrets resource can be used to secure the database connection string. In our `secrets.yml` file we set secrets:
```YAML
apiVersion: v1
kind: Secret
metadata:
  name: db-secrets
type: Opaque
data:
  secrets.txt: <Base64-Encoded-String>

#secrets.txt: db=DB_NAME&dbuser=DB_USERNAME&dbpw=DB_PASSWORD&dbhost=DB_HOST
```
> To output base64 encoded strings for use in your `secrets.yml`, use the command:
  ```BASH
  $ echo -n "<string to encode>" | base64 -w 0
  ```

These secrets are mounted in volumeMounts within our `deployment.yaml` file:
```YAML
volumes:
- name: secrets-vol
  secret:
    secretName: db-secrets
volumeMounts:
- mountPath: /var/www/html/config/secrets.txt
  name: secrets-vol
  subPath: secrets.txt
  readOnly: true
```
In our Drupal `settings.php` file, we consume the variables in the `$databases` array:

```PHP
$secret = file_get_contents('/var/www/html/config/secrets.txt');
$secret = trim($secret);
$dbconnstring = parse_str($secret,$output);
$databases = array (
  'default' =>
  array (
    'default' =>
    array (
      'database' => $output['db'],
      'username' => $output['dbuser'],
      'password' => $output['dbpw'],
      'prefix' => '',
      'host' => $output['dbhost'],
      'port' => '3306',
      'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',
      'driver' => 'mysql',
    ),
  ),
);
```

<a id="files"></a>
## Persistent Files

The persistence of files is critical for a CMS website like Drupal. Examples of persisted files include:

- Unstructured data such as images and documents that are uploaded by content creators, i.e. not part of the code repo.
- Logs such as `php-error.log` and `drupal.log` (when the Drupal core Syslog module is enabled).
- Configurations that use files outside the repo such as these `settings.php` examples:
  ```PHP
  /**
  * Salt for one-time login links, cancel links, form tokens, etc. 
  *
  * Include your salt value in a salt.txt file and reference it with:
  */
  $settings['hash_salt'] = file_get_contents('/var/www/html/config/salt.txt');
  
  /* 
  * Storage location of the sync directory.
  */

  $settings['config_sync_directory'] = '../config/sync'; // Drupal 8.8.x
  
  $config_directories['sync'] = '../config/sync'; // Drupal 8.0.0 to 8.7.x
  ```
To persist files, we mount to Azure Storage persistent volumes that are provided by the `azure-file` or `azure-file-premium` Storage Classes in AKS: 
```
michael@Azure:~$ kubectl get storageclass
NAME                PROVISIONER                AGE
azurefile           kubernetes.io/azure-file   19d
azurefile-premium   kubernetes.io/azure-file   19d
default (default)   kubernetes.io/azure-disk   3d8h
managed-premium     kubernetes.io/azure-disk   3d8h
```
Azure Files is our storage class of choice because its ReadWriteMany access mode allows for horizontal pod scaling, i.e. across nodes. For production deployment, `azurefile-premium` is recommended for best performance.

Volume mounts are declared in the `manifests/deployment.yml` file:
```YAML
volumeMounts:
- mountPath: /var/log/apache2
  name: apache2-vol
- mountPath: /var/www/html/docroot/sites/default/files
  name: files-vol
- mountPath: /var/www/html/config
  name: config-vol
- mountPath: /var/www/html/config/secrets.txt
  name: secrets-vol
  subPath: secrets.txt
  readOnly: true
```
> **Tip**: Use [Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/) to access and manage your Azure Storage resources.


<a id="implementation"></a>
## Implementation

### Step 1 - Build and push your Docker image

Ensure that your [Prerequisites](#prerequisites) are in place.

Clone this repo to your local dev environment. 

Edit the the following section of the `Dockerfile` to point to the source for your Drupal code:
```DOCKER
# Copy drupal code
WORKDIR /var/www/html
COPY . /var/www/html
# Alternatively you can clone from a remote repository, e.g.
# RUN git clone -b $BRANCH https://$GIT_TOKEN@github.com/$GIT_REPO.git .
```
Build the docker image locally:
```
docker build -t <image-name> .
docker tag <image-name> <registry>/<image-name>:<tag> 
docker push <registry>/<image-name>:<tag>  
```
*For example, using Azure Container Registry:*
```
docker build -t drupal8aks .
docker tag drupal8aks myacr.azurecr.io/drupalaks:v1
docker push myacr.azurecr.io/drupalaks:v1  
```

### Step 2 - Deploy to AKS

1. Customize the `image:` value in the `containers:` spec if the `deployment.yml` manifest, e.g.
    ```YAML
    containers:
        -
          image: myacr.azurecr.io/drupalaks:v1
    ```
2. Customize the encoded values in the `db-secrets.yml` and `sa-secrets.yml` manifests, e.g.
    ```
    secrets.txt: <Base64-Encoded-String>
    ```
3. In the `pvc.yml` manifest, change the `storageClassName` to `azure-file`, if you prefer to use the Standard_LRS SKU.


4. Finally, deploy the kubernetes manifests using the commands:
   ```
   kubectl apply -f manifests/db-secrets.yml
   kubectl apply -f manifests/sa-secrets.yml
   kubectl apply -f manifests/pv-pvc.yml
   kubectl apply -f manifests/service.yml
   kubectl apply -f manifests/deployment.yml
   ```

### Step 3 - Validate the deployment
Validate the deployment by accessing the website via the IP Address exposed by the Kubernetes LoadBalancer service. To identify the IP Address, use the command:
```
$ kubectl get svc drupal-service
NAME             TYPE           CLUSTER-IP   EXTERNAL-IP      PORT(S)        AGE
drupal-service   LoadBalancer   10.2.0.50    52.151.xxx.xxx   80:32758/TCP   10d
```
<a id="references"></a>
## References

* [Azure Kubernetes Documentation](https://docs.microsoft.com/en-us/azure/aks/intro-kubernetes)
* [Azure Kubernetes Service Workshop](https://docs.microsoft.com/en-us/learn/modules/aks-workshop/) by Microsoft Learn
* [Docker Hub Official Repository for php](https://hub.docker.com/r/_/php/)
* [Azure Database for MySQL documentation](https://docs.microsoft.com/en-us/azure/mysql/) or [MariaDB](https://docs.microsoft.com/en-us/azure/Mariadb/)* 

Git repository sponsored by [SNP Technologies](https://www.snp.com)
