# configure providers
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
}

locals {
    subscription_id           = ""
    tenant_id                 = ""
    rg_name                   = "testtf"
    location                  = "westus2"
    namespace                 = "demossl"
    ingressClass              = "demo"
    hostname                  = "test-demo-letsencrypt-ssl" # change this to whatver you like. The full url for this hostname with ssl would be https://demo-letsencrypt-ssl.westus2.cloudapp.azure.com
    ssl_cert_owner_email      = "admin@myorg.com" # email for let's encrypt to contact
}

provider "azurerm" {
  features {}
  subscription_id = local.subscription_id
  tenant_id       = local.tenant_id
}

resource "azurerm_kubernetes_cluster" "demo" {
  name                = "demoaks"
  location            = local.location
  resource_group_name = local.rg_name
  dns_prefix          = "demoaksdns"
  kubernetes_version  = "1.25.4"

  default_node_pool {
    name       = "cpupool1"
    enable_auto_scaling = true
    vm_size    = "Standard_D2s_v3"
    min_count = 1 
    max_count = 3
  }

  identity {
    type = "SystemAssigned"
  }
}

# create public ip for this aks
resource "azurerm_public_ip" "demo_public_ip" {
  name                = "demo-ip"
  resource_group_name = azurerm_kubernetes_cluster.demo.node_resource_group
  location            = local.location
  allocation_method   = "Static"
  sku = "Standard"

  domain_name_label = local.hostname
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.demo.kube_config.0.host
  username               = azurerm_kubernetes_cluster.demo.kube_config.0.username
  password               = azurerm_kubernetes_cluster.demo.kube_config.0.password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.demo.kube_config.0.host
    username               = azurerm_kubernetes_cluster.demo.kube_config.0.username
    password               = azurerm_kubernetes_cluster.demo.kube_config.0.password
    client_certificate     = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.demo.kube_config.0.host
  username               = azurerm_kubernetes_cluster.demo.kube_config.0.username
  password               = azurerm_kubernetes_cluster.demo.kube_config.0.password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.demo.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}

# create namespace
resource "kubernetes_namespace" "ns" {
  metadata {
    labels = {
        "certmanager.k8s.io/disable-validation" = "true"
    }
    name = local.namespace
  }
  depends_on = [
    azurerm_kubernetes_cluster.demo
  ]
}


# install nginx_ingress
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "${local.namespace}"
  version    = "4.4.2"
  wait       = true

  set {
    name = "controller.ingressClassResource.name"
    value = "${local.ingressClass}"
  }
  set {
    name = "controller.scope.enabled"
    value = true
  }
  set {
    name = "controller.scope.namespace"
    value = "${local.namespace}"
  }
  set {
    name = "controller.ingressClass"
    value = "${local.ingressClass}"
  }
  set {
    name  = "controller.replicaCount"
    value = 2
  }
  set {
    name  = "controller.nodeSelector\\.kubernetes.io/os"
    value = "linux"
  }
  set {
    name  = "controller.image.registry"
    value = "k8s.gcr.io"
  }
  set {
    name  = "controller.image.image"
    value = "ingress-nginx/controller"
  }
  set {
    name  = "controller.image.tag"
    value = "v1.2.1"
  }
  set {
    name  = "controller.image.digest"
    value = ""
  }
  set {
    name  = "controller.admissionWebhooks.patch.nodeSelector\\.kubernetes.io/os"
    value = "linux"
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.registry"
    value = "k8s.gcr.io"
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.image"
    value = "ingress-nginx/kube-webhook-certgen"
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.tag"
    value = "v1.1.1"
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.digest"
    value = ""
  }

  set {
    name  = "defaultBackend.nodeSelector\\.kubernetes.io/os"
    value = "linux"
  }
  set {
    name  = "defaultBackend.image.registry"
    value = "k8s.gcr.io"
  }
  set {
    name  = "defaultBackend.image.image"
    value = "defaultbackend-amd64"
  }
  set {
    name  = "defaultBackend.image.tag"
    value = "1.5"
  }
  set {
    name  = "defaultBackend.image.digest"
    value = ""
  }
  set {
    name  = "controller.service.loadBalancerIP"
    value = "${azurerm_public_ip.demo_public_ip.ip_address}"
  }
  set {
    name  = "controller.service.annotations\\.service.beta.kubernetes.io/azure-dns-label-name"
    value = "${local.hostname}"
  }    
  #set {
  #  name  = "controller.service.annotations\\.service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path"
  #  value = "/healthz"
  #}
  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
  depends_on = [
    kubernetes_namespace.ns
  ]
}

# Install cert-manager - cert-manager can be shared across multiple nginx servers
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.11.0"
  namespace  = "${local.namespace}"

  set {
    name  = "installCRDs"
    value = true
  }
  set {
    name  = "controller.nodeSelector\\.beta.kubernetes.io/os"
    value = "linux"
  }
  set {
    name  = "image.repository"
    value = "quay.io/jetstack/cert-manager-controller"
  }
  set {
    name  = "image.tag"
    value = "v1.11.0"
  }
  set {
    name  = "webhook.image.repository"
    value = "quay.io/jetstack/cert-manager-webhook"
  }
  set {
    name  = "webhook.image.tag"
    value = "v1.11.0"
  }
  set {
    name  = "cainjector.image.repository"
    value = "quay.io/jetstack/cert-manager-cainjector"
  }
  set {
    name  = "cainjector.image.tag"
    value = "v1.11.0"
  }
  depends_on = [
    helm_release.nginx_ingress
  ]
}

resource "kubectl_manifest" "ca_issuer" {
  wait = true
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt-prod
  namespace: "${local.namespace}"
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: "${local.ssl_cert_owner_email}"
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: "${local.ingressClass}"
          podTemplate:
            spec:
              nodeSelector:
                "kubernetes.io/os": linux
  YAML
  depends_on = [
    helm_release.cert_manager
  ]
}

# create api-service and ing-service
resource "kubectl_manifest" "api_service" {
  wait = true
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  namespace: "${local.namespace}"
  name: web-svc
spec:
  # type: LoadBalancer
  clusterIP: None
  ports:
    - name: http
      port: 80
  selector:
    name: web-svc
  YAML
  depends_on = [
    kubernetes_namespace.ns
  ]
}

resource "kubectl_manifest" "ing_service" {
  wait = true
  yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: "${local.namespace}"
  name: web-ing
  annotations:
    cert-manager.io/issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$1
spec:
  ingressClassName: "${local.ingressClass}"
  tls:
  - hosts:
    - ${azurerm_public_ip.demo_public_ip.fqdn}
    secretName: tls-secret
  rules:
  - host: ${azurerm_public_ip.demo_public_ip.fqdn}
    http:
      paths:
      - path: /(.*)
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
  YAML
  depends_on = [
    kubernetes_namespace.ns, kubectl_manifest.ca_issuer
  ]
}
