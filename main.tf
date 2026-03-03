data "azurerm_client_config" "current" {}
# Random suffix for unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
locals {
  common_tags = {

    Project   = var.project_name
    ManagedBy = "Terraform"
    Owner     = "Solutions Architect"
  }
}
resource "azurerm_network_security_group" "private_nsg" {
  name                = "nsg-private"
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
resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private_nsg.id
}


resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${terraform.workspace}-${random_string.suffix.result}"
  location = var.location

  tags = local.common_tags
}

# resource "azurerm_storage_account" "main" {
#   name                     = "st${var.project_name}${random_string.suffix.result}"
#   resource_group_name      = azurerm_resource_group.main.name
#   location                 = azurerm_resource_group.main.location
#   account_tier             = "Standard"
#   account_replication_type = terraform.workspace == "prod" ? "GRS" : "LRS"

#   tags = local.common_tags
# }
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]

  tags = local.common_tags
}

resource "azurerm_subnet" "private" {
  name                 = "snet-private"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}
resource "azurerm_key_vault" "main" {
  name                          = "kv-${var.project_name}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = local.common_tags
}

resource "azurerm_private_endpoint" "kv_pe" {
  name                = "pe-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private.id

  private_service_connection {
    name                           = "kv-connection"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}
#checkov:skip=CKV_AZURE_33:Using azurerm v4 retention_policy_days schema
resource "azurerm_storage_account" "main" {
  name                     = lower("st${var.project_name}${random_string.suffix.result}")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"


  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  https_traffic_only_enabled      = true

  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}
#checkov:skip=CKV_AZURE_33:Using azurerm v4 retention_policy_days schema
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
resource "azurerm_private_endpoint" "storage_pe" {
  name                = "pe-storage"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private.id

  private_service_connection {
    name                           = "storage-priv-conn"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
resource "azurerm_key_vault_key" "cmk" {
  name         = "storage-cmk"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 2048

  expiration_date = "2027-12-31T00:00:00Z"

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "verify",
    "wrapKey",
    "unwrapKey"
  ]
}

resource "azurerm_storage_account_customer_managed_key" "cmk" {
  storage_account_id = azurerm_storage_account.main.id
  key_vault_key_id   = azurerm_key_vault_key.cmk.id
}
