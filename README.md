# aks_letsencrypt
AKS Cluster SSL endpoint with letsencrypt

## Configure the deployment

### Version
Tested with the following versions:  
AKS Version: 1.25.4  
ingress-nginx: 4.4.2  
    controller.image.tag: v1.2.1  
    controller.admissionWebhooks.tag: v1.1.1  
    defaultBackend.image.tag: 1.5  
cert-manager: v1.11.0   
    tags: v1.11.0  
    
```yaml    
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 3.40"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">=2.33.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = ">= 2.17.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }    
  }
```


### Update main.tf

Add subscription_id and tenant_id values in infra\main.tf.

## Deploy infrastructure

cd infra  
terraform init  
terraform apply  

