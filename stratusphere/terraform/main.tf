# =====================================================================
# AVD readiness with Stratusphere UX -- assessment environment
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#
# One resource group per assessment: a small VNet (optionally peered to the
# network the endpoints live in), Key Vault for the appliance credential, an
# optional Azure Bastion for the console, and the Stratusphere Hub appliance
# from Azure Marketplace. Bring your own Stratusphere license.
# =====================================================================

data "azurerm_client_config" "current" {}

locals {
  suffix         = substr(sha256("${data.azurerm_client_config.current.subscription_id}:${var.namePrefix}:${var.location}"), 0, 5)
  rg_name        = var.environment == "" ? "rg-${var.namePrefix}-stratusphere" : "rg-${var.namePrefix}-${var.environment}-stratusphere"
  vnet_name      = "vnet-${var.namePrefix}-stratusphere"
  bastion_name   = "bas-${var.namePrefix}-stratusphere"
  key_vault_name = "kv-${var.namePrefix}-ss-${local.suffix}"

  # Collectors write to the database: on the Database appliance, or on the Hub without one.
  allow_postgres = var.deployDatabase || var.collectorCount > 0
  peer           = var.peerVirtualNetworkResourceId != ""

  all_tags = merge(
    {
      workload     = "stratusphere-assessment"
      "managed-by" = "avd-liquidware"
    },
    var.tags
  )
}

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = local.all_tags
}
