# Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Configure Azure Provider
provider "azurerm" {
  features {}
  subscription_id = var.subscriptionID
  # client_id       = "your-client-id"
  # client_secret   = "your-client-secret"
  # tenant_id       = "your-tenant-id"
}

# Helm
provider "helm" {
  kubernetes {
    host               = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    client_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)

    # If your cluster uses a custom context, uncomment and set it here
    # context = "your-aks-cluster-context" 
  }
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "igor_candidate"
  location = "East US"
}


# Key Vault
resource "azurerm_key_vault" "kv" {
  name                = "igorkv2bcloud"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = var.tenant_id

  sku_name = "standard"

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete"
    ]
  }
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "my-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "my-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "my-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP for Nginx Ingress Controller (Static)
resource "azurerm_public_ip" "nginx_ingress_pip" {
  name                = "nginx-ingress-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = "my-nginx-ingress" # Replace with your desired domain prefix
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "my-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "my-ip-config"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = null # No public IP for the VM directly
  }
}

# Virtual Machine (Ubuntu with Jenkins)
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "jenkins-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_B2pls_v2" # az vm list-skus --location eastus --resource-type virtualMachines --zone --all --output table
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/ib.pub") # Replace with your SSH public key path
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18_04-daily-lts-arm64" # az vm image list --all --publisher="Canonical" --offer="UbuntuServer"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    # Install Docker
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io

    # Install Git
    apt-get install -y git

    # Install Jenkins (Adapt as needed)
    wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | apt-key add -
    sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
    apt-get update
    apt-get install -y jenkins
  EOF
  )
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-cluster-v1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-cluster-v1"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "standard_b2pls_v2"
  }

  identity {
    type = "SystemAssigned"
  }


  # linux_profile {
  #   admin_username = "azureuser"
  #   ssh_key {
  #     key_data = file("~/.ssh/ib.pub") # Replace with your SSH public key path
  #   }
  # }

# If network_profile is not defined, kubenet profile will be used by default.
  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }
}

# Azure Container Registry (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "igoracr2bcloud"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"

  admin_enabled = false
}

# Cert-Manager (with External DNS and Workload Identity)
resource "helm_release" "cert_manager" {
  provider         = helm
  name             = "cert-manager"
  namespace        = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.12.0" # Replace with the latest version
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Configure External DNS integration (Replace placeholders)
  set {
    name  = "extraArgs[0]"
    value = "--dns01-recursive-nameservers=8.8.8.8:53\\,8.8.4.4:53"
  }

  set {
    name  = "extraArgs[1]"
    value = "--dns01-recursive-nameservers-only"
  }

  set {
    name  = "externalDNS.provider"
    value = "azure"
  }
  set {
    name  = "externalDNS.azure.resourceGroupName"
    value = azurerm_resource_group.rg.name
  }
  set {
    name  = "externalDNS.azure.tenantID"
    value = var.tenant_id
  }
  set {
    name  = "externalDNS.azure.subscriptionID"
    value = var.subscriptionID
  }
  # set {
  #   name  = "externalDNS.azure.aadClientID"
  #   value = "<Your Azure AD App Client ID>" # Replace with your actual ID
  # }
  set {
    name  = "externalDNS.azure.aadClientSecretSecretRef.name"
    value = "azure-dns-secret"
  }
  set {
    name  = "externalDNS.azure.aadClientSecretSecretRef.key"
    value = "client-secret"
  }
  set {
    name  = "externalDNS.txtOwnerId"
    value = "cert-manager"
  }

  # # Configure Workload Identity (Replace placeholders)
  # set {
  #   name  = "serviceAccount.annotations.azure\\. workload\\.identity/client\\.id"
  #   value = "<Your Workload Identity Client ID>"
  # }
}

# Nginx Ingress Controller (with Static IP and DNS)
resource "helm_release" "nginx_ingress" {
  provider   = helm
  name       = "nginx-ingress"
  namespace  = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  wait             = false # Added due to timeout error
  create_namespace = false
  version          = "4.4.0"

  set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.nginx_ingress_pip.ip_address
  }
  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }
  set {
    name  = "controller.ingressClassResource.name"
    value = "nginx"
  }
}
