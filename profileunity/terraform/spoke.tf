# Writes to the landing zone network resource group, and only these (deploy-spec section 4):
# the spoke side of the peering and the links from the landing zone's privatelink zones to the
# tier VNet. All are child resources, so a landing zone redeploy leaves them alone, and Cleanup
# removes them.

locals {
  file_dns_zone_name  = element(split("/", var.fileDnsZoneId), length(split("/", var.fileDnsZoneId)) - 1)
  vault_dns_zone_name = element(split("/", var.vaultDnsZoneId), length(split("/", var.vaultDnsZoneId)) - 1)
}

resource "azurerm_virtual_network_peering" "to_tier" {
  name                         = "peer-${local.base}-to-liquidware"
  resource_group_name          = local.spoke_resource_group
  virtual_network_name         = local.spoke_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.tier.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "link-${local.base}-liquidware"
  resource_group_name   = local.spoke_resource_group
  private_dns_zone_name = local.file_dns_zone_name
  virtual_network_id    = azurerm_virtual_network.tier.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "link-${local.base}-liquidware"
  resource_group_name   = local.spoke_resource_group
  private_dns_zone_name = local.vault_dns_zone_name
  virtual_network_id    = azurerm_virtual_network.tier.id
  registration_enabled  = false
}
