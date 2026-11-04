# Ops runner identity, Key Vault, live config account, packages account, media account, and
# private endpoints (deploy-spec section 5).

# ---------- Identity ----------

resource "azurerm_user_assigned_identity" "ops" {
  name                = "id-${local.base}-lw-ops"
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  tags                = local.all_tags
}

# ---------- Key Vault ----------

resource "azurerm_key_vault" "tier" {
  name                          = local.key_vault_name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.tier.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  tags                          = local.all_tags

  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }
}

# ---------- Live config account ----------

resource "azurerm_storage_account" "config" {
  name                            = local.config_account_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.tier.name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = false
  tags                            = merge(local.all_tags, { "liquidware-role" = "config" })

  network_rules {
    bypass         = ["None"]
    default_action = "Deny"
  }

  azure_files_authentication {
    directory_type                 = "AADKERB"
    default_share_level_permission = "None"
  }

  share_properties {
    smb {
      versions                        = local.smb_hardened.versions
      authentication_types            = local.smb_hardened.authentication_types
      kerberos_ticket_encryption_type = local.smb_hardened.kerberos_ticket_encryption_type
      channel_encryption_type         = local.smb_hardened.channel_encryption_type
    }
  }
}

resource "azurerm_storage_share" "lwconfig" {
  name               = "lwconfig"
  storage_account_id = azurerm_storage_account.config.id
  quota              = 5
  enabled_protocol   = "SMB"
}

# Users read the INI their logon applies and can't change it (tier N-C1).
resource "azurerm_role_assignment" "config_users_read" {
  scope              = azurerm_storage_account.config.id
  role_definition_id = local.role_definition_ids.smbShareReader
  principal_id       = var.usersGroupObjectId
  principal_type     = "Group"
}

# The only writer: the ops runner, after the promote checks (deploy-spec section 7).
resource "azurerm_role_assignment" "config_ops_write" {
  scope              = azurerm_storage_account.config.id
  role_definition_id = local.role_definition_ids.filePrivilegedContributor
  principal_id       = azurerm_user_assigned_identity.ops.principal_id
  principal_type     = "ServicePrincipal"
}

# ---------- Packages account ----------

# Tier spec section 5.1: the one account with shared key on, for app attach images only.
resource "azurerm_storage_account" "packages" {
  name                            = local.packages_account_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.tier.name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = false
  tags                            = merge(local.all_tags, { "liquidware-role" = "packages" })

  network_rules {
    bypass         = ["None"]
    default_action = "Deny"
  }

  share_properties {
    smb {
      versions                        = local.smb_hardened.versions
      authentication_types            = ["NTLMv2", "Kerberos"]
      kerberos_ticket_encryption_type = local.smb_hardened.kerberos_ticket_encryption_type
      channel_encryption_type         = local.smb_hardened.channel_encryption_type
    }
  }
}

resource "azurerm_storage_share" "appattach" {
  name               = "appattach"
  storage_account_id = azurerm_storage_account.packages.id
  quota              = 100
  enabled_protocol   = "SMB"
}

resource "azurerm_role_assignment" "packages_avd_read" {
  for_each           = toset(var.avdServicePrincipalObjectIds)
  scope              = azurerm_storage_account.packages.id
  role_definition_id = local.role_definition_ids.readerAndDataAccess
  principal_id       = each.value
  principal_type     = "ServicePrincipal"
}

# ---------- Media account ----------

# Installers in `media`, compiled configuration from the console in `staging` (deploy-spec section 5,
# fork F4). Shared key and anonymous access off; public endpoint on with Entra-only data plane (D-C4).
resource "azurerm_storage_account" "media" {
  name                            = local.media_account_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.tier.name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  tags                            = merge(local.all_tags, { "liquidware-role" = "media" })
}

resource "azurerm_storage_container" "media" {
  name                  = "media"
  storage_account_id    = azurerm_storage_account.media.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "staging" {
  name                  = "staging"
  storage_account_id    = azurerm_storage_account.media.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "operator_media" {
  scope              = azurerm_storage_container.media.resource_manager_id
  role_definition_id = local.role_definition_ids.blobDataContributor
  principal_id       = var.operatorObjectId
  principal_type     = "User"
}

resource "azurerm_role_assignment" "ops_staging" {
  scope              = azurerm_storage_container.staging.resource_manager_id
  role_definition_id = local.role_definition_ids.blobDataReader
  principal_id       = azurerm_user_assigned_identity.ops.principal_id
  principal_type     = "ServicePrincipal"
}

# ---------- Private endpoints ----------

locals {
  private_endpoints = {
    vault = {
      name      = "pe-${local.key_vault_name}"
      target_id = azurerm_key_vault.tier.id
      group_id  = "vault"
      zone_id   = var.vaultDnsZoneId
    }
    config = {
      name      = "pe-${local.config_account_name}-file"
      target_id = azurerm_storage_account.config.id
      group_id  = "file"
      zone_id   = var.fileDnsZoneId
    }
    packages = {
      name      = "pe-${local.packages_account_name}-file"
      target_id = azurerm_storage_account.packages.id
      group_id  = "file"
      zone_id   = var.fileDnsZoneId
    }
  }
}

resource "azurerm_private_endpoint" "tier" {
  for_each            = local.private_endpoints
  name                = each.value.name
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.all_tags

  private_service_connection {
    name                           = each.value.name
    private_connection_resource_id = each.value.target_id
    subresource_names              = [each.value.group_id]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [each.value.zone_id]
  }
}
