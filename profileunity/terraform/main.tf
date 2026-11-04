# The Liquidware tier's network and storage against an existing avd-landing-zone landing zone
# (docs/deploy-spec.md sections 4 and 5). Deploy-LiquidwareTier.ps1 discovers the landing zone and
# passes what it found; nothing here reads the landing zone by itself.
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.
#
# Native azurerm resources rather than module wrappers: the template tests check every role
# assignment's scope and principal directly.

data "azurerm_client_config" "current" {}

locals {
  clean = replace(lower(var.namePrefix), "-", "")
  base  = "${local.clean}-${var.environment}"
  uniq  = substr(sha256("${data.azurerm_client_config.current.subscription_id}:${local.base}:liquidware"), 0, 5)

  all_tags = merge(var.tags, {
    workload              = "liquidware"
    "landing-zone"        = local.base
    "avdlz-power-managed" = local.base
  })

  spoke_parts          = split("/", var.spokeVnetId)
  spoke_resource_group = local.spoke_parts[4]
  spoke_vnet_name      = local.spoke_parts[8]

  vnet_name             = "vnet-${local.base}-liquidware"
  key_vault_raw         = "kv${local.clean}${var.environment}lw${local.uniq}"
  key_vault_name        = substr(local.key_vault_raw, 0, min(24, length(local.key_vault_raw)))
  config_account_raw    = "st${local.clean}${var.environment}lwc${local.uniq}"
  config_account_name   = substr(local.config_account_raw, 0, min(24, length(local.config_account_raw)))
  packages_account_raw  = "st${local.clean}${var.environment}lwp${local.uniq}"
  packages_account_name = substr(local.packages_account_raw, 0, min(24, length(local.packages_account_raw)))
  media_account_raw     = "st${local.clean}${var.environment}lwm${local.uniq}"
  media_account_name    = substr(local.media_account_raw, 0, min(24, length(local.media_account_raw)))

  console_vm_name       = "vm-${local.clean}lwcon"
  console_computer_name = substr("${local.clean}lwcon", 0, min(15, length("${local.clean}lwcon")))
  packaging_vm_name     = "vm-${local.clean}lwpkg"
  packaging_computer    = substr("${local.clean}lwpkg", 0, min(15, length("${local.clean}lwpkg")))

  # Built-in role definition IDs: the same in every tenant.
  roles = {
    smbShareReader            = "aba4ae5f-2193-4029-9191-0cb91df5e314"
    filePrivilegedContributor = "69566ab7-960f-475b-8e7c-b3118f30c6bd"
    readerAndDataAccess       = "c12c1c16-33a1-487b-954d-41c89c60f349"
    blobDataContributor       = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    blobDataReader            = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
    keyVaultSecretsUser       = "4633458b-17de-408a-b874-0445c86b69e6"
  }

  role_definition_ids = {
    for k, id in local.roles : k => "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${id}"
  }

  # The profiles account's SMB settings (avd-landing-zone lesson 0028: both GCM channels, or
  # Entra Kerberos clients get access denied). Multichannel is Premium-only, so it is left out.
  smb_hardened = {
    versions                        = ["SMB3.1.1"]
    authentication_types            = ["Kerberos"]
    kerberos_ticket_encryption_type = ["AES-256"]
    channel_encryption_type         = ["AES-128-GCM", "AES-256-GCM"]
  }
}

resource "azurerm_resource_group" "tier" {
  name     = "rg-${local.base}-liquidware"
  location = var.location
  tags     = local.all_tags
}
