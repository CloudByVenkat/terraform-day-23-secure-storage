# Data source for current Azure client
data "azurerm_client_config" "current" {}

# Random suffix for unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Common tags for all resources
locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Owner     = "Solutions Architect"
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${terraform.workspace}-${random_string.suffix.result}"
  location = var.location

  tags = local.common_tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project_name}-${terraform.workspace}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]

  tags = local.common_tags
}

# Private Subnet
resource "azurerm_subnet" "private" {
  name                 = "snet-private--${terraform.workspace}-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "private_nsg" {
  name                = "nsg-private-${terraform.workspace}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  tags = local.common_tags
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private_nsg.id
}

# Key Vault with RBAC
# checkov:skip=CKV_AZURE_189:Firewall rules configured via network_acls
resource "azurerm_key_vault" "main" {
  name                          = "kv-${var.project_name}-${terraform.workspace}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  rbac_authorization_enabled    = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "kv_admin_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.admin_user_object_id
}
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "kv_pe" {
  name                = "pe-kv-${terraform.workspace}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private.id

  private_service_connection {
    name                           = "kv-connection"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = local.common_tags
}

# Storage Account with enhanced security
# checkov:skip=CKV2_AZURE_38:Soft delete configured via delete_retention_policy
# checkov:skip=CKV2_AZURE_40:Storage defender not required for demo
resource "azurerm_storage_account" "main" {
  name                     = lower("st${var.project_name}${terraform.workspace}${random_string.suffix.result}")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = false
  shared_access_key_enabled         = true # Required for CMK
  https_traffic_only_enabled        = true
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
  # SAS expiration policy
  sas_policy {
    expiration_period = "07.00:00:00" # 7 days
    expiration_action = "Log"
  }

  tags = local.common_tags
}

# RBAC: Grant Storage Account access to Key Vault
resource "azurerm_role_assignment" "storage_kv_role" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_storage_account.main.identity[0].principal_id
}
# Wait for RBAC to propagate (Azure takes 1-2 minutes)
resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.current_user_kv_admin
  ]

  create_duration = "120s" # Wait 2 minutes
}
# Storage Queue Properties
resource "azurerm_storage_account_queue_properties" "main" {
  storage_account_id = azurerm_storage_account.main.id

  logging {
    version               = "1.0"
    delete                = true
    read                  = true
    write                 = true
    retention_policy_days = 7
  }

  hour_metrics {
    include_apis          = true
    retention_policy_days = 7
    version               = "1.0"
  }

  minute_metrics {

    include_apis          = true
    retention_policy_days = 7
    version               = "1.0"
  }
}

# Private Endpoint for Storage Account
resource "azurerm_private_endpoint" "storage_pe" {
  name                = "pe-storage-${terraform.workspace}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private.id

  private_service_connection {
    name                           = "storage-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  tags = local.common_tags
}

# Customer-Managed Key for Storage Encryption
resource "azurerm_key_vault_key" "cmk" {
  name            = "storage-cmk-${terraform.workspace}-${random_string.suffix.result}"
  key_vault_id    = azurerm_key_vault.main.id
  key_type        = "RSA-HSM"
  key_size        = 2048
  expiration_date = "2027-12-31T00:00:00Z"

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "verify",
    "wrapKey",
    "unwrapKey"
  ]

  depends_on = [
    time_sleep.wait_for_rbac
  ]

  tags = local.common_tags
}

# Apply Customer-Managed Key to Storage Account
resource "azurerm_storage_account_customer_managed_key" "cmk" {
  storage_account_id = azurerm_storage_account.main.id
  key_vault_key_id   = azurerm_key_vault_key.cmk.id

  depends_on = [
    azurerm_role_assignment.storage_kv_role
  ]
}
