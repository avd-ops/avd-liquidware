# Tier network in rg-<base>-liquidware (deploy-spec section 5): NAT Gateway, NSGs that deny
# outbound to the spoke except its private endpoint subnet (DN-M1), VNet with default outbound
# access off on every subnet, and the tier side of the spoke peering.

locals {
  tier_prefix_length = tonumber(split("/", var.tierAddressPrefix)[1])

  # 10.61.0.0/24 by default: console .0/27, endpoints .32/27, packaging .64/27, ops .96/28,
  # AzureBastionSubnet .128/26.
  subnets = {
    console   = cidrsubnet(var.tierAddressPrefix, 27 - local.tier_prefix_length, 0)
    endpoints = cidrsubnet(var.tierAddressPrefix, 27 - local.tier_prefix_length, 1)
    packaging = cidrsubnet(var.tierAddressPrefix, 27 - local.tier_prefix_length, 2)
    ops       = cidrsubnet(var.tierAddressPrefix, 28 - local.tier_prefix_length, 6)
    bastion   = cidrsubnet(var.tierAddressPrefix, 26 - local.tier_prefix_length, 2)
  }

  # Bicep cidrHost(subnets.console, 3) is 0-indexed on usable hosts (.4); Terraform cidrhost is
  # 0-indexed from the network address, so hostnum 4 is 10.61.0.4.
  console_private_ip = cidrhost(local.subnets.console, 4)
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-ng-${local.vnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.all_tags
}

resource "azurerm_nat_gateway" "tier" {
  name                    = "ng-${local.vnet_name}"
  location                = var.location
  resource_group_name     = azurerm_resource_group.tier.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = local.all_tags
}

resource "azurerm_nat_gateway_public_ip_association" "tier" {
  nat_gateway_id       = azurerm_nat_gateway.tier.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_network_security_group" "console" {
  name                = "nsg-${local.vnet_name}-console"
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  tags                = local.all_tags

  security_rule {
    name                       = "Allow-Licensing-From-Session-Hosts"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.sessionHostSubnetPrefix
    source_port_range          = "*"
    destination_address_prefix = local.subnets.console
    destination_port_range     = "443"
  }

  dynamic "security_rule" {
    for_each = var.deployBastion ? [1] : []
    content {
      name                       = "Allow-Rdp-From-Bastion"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = local.subnets.bastion
      source_port_range          = "*"
      destination_address_prefix = local.subnets.console
      destination_port_range     = "3389"
    }
  }

  security_rule {
    name                       = "Deny-Other-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "Allow-Spoke-Private-Endpoints"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = var.spokePrivateEndpointSubnetPrefix
    destination_port_range     = "*"
  }

  security_rule {
    name                         = "Deny-Spoke"
    priority                     = 110
    direction                    = "Outbound"
    access                       = "Deny"
    protocol                     = "*"
    source_address_prefix        = "*"
    source_port_range            = "*"
    destination_address_prefixes = var.spokeAddressPrefixes
    destination_port_range       = "*"
  }
}

resource "azurerm_network_security_group" "packaging" {
  name                = "nsg-${local.vnet_name}-packaging"
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  tags                = local.all_tags

  dynamic "security_rule" {
    for_each = var.deployBastion ? [1] : []
    content {
      name                       = "Allow-Rdp-From-Bastion"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = local.subnets.bastion
      source_port_range          = "*"
      destination_address_prefix = local.subnets.packaging
      destination_port_range     = "3389"
    }
  }

  security_rule {
    name                       = "Deny-Other-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "Allow-Spoke-Private-Endpoints"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = var.spokePrivateEndpointSubnetPrefix
    destination_port_range     = "*"
  }

  security_rule {
    name                         = "Deny-Spoke"
    priority                     = 110
    direction                    = "Outbound"
    access                       = "Deny"
    protocol                     = "*"
    source_address_prefix        = "*"
    source_port_range            = "*"
    destination_address_prefixes = var.spokeAddressPrefixes
    destination_port_range       = "*"
  }
}

resource "azurerm_virtual_network" "tier" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  address_space       = [var.tierAddressPrefix]
  tags                = local.all_tags
}

resource "azurerm_subnet" "console" {
  name                            = "snet-lw-console"
  resource_group_name             = azurerm_resource_group.tier.name
  virtual_network_name            = azurerm_virtual_network.tier.name
  address_prefixes                = [local.subnets.console]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "console" {
  subnet_id                 = azurerm_subnet.console.id
  network_security_group_id = azurerm_network_security_group.console.id
}

resource "azurerm_subnet_nat_gateway_association" "console" {
  subnet_id      = azurerm_subnet.console.id
  nat_gateway_id = azurerm_nat_gateway.tier.id
}

resource "azurerm_subnet" "endpoints" {
  name                              = "snet-lw-endpoints"
  resource_group_name               = azurerm_resource_group.tier.name
  virtual_network_name              = azurerm_virtual_network.tier.name
  address_prefixes                  = [local.subnets.endpoints]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "packaging" {
  name                            = "snet-lw-packaging"
  resource_group_name             = azurerm_resource_group.tier.name
  virtual_network_name            = azurerm_virtual_network.tier.name
  address_prefixes                = [local.subnets.packaging]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "packaging" {
  subnet_id                 = azurerm_subnet.packaging.id
  network_security_group_id = azurerm_network_security_group.packaging.id
}

resource "azurerm_subnet_nat_gateway_association" "packaging" {
  subnet_id      = azurerm_subnet.packaging.id
  nat_gateway_id = azurerm_nat_gateway.tier.id
}

resource "azurerm_subnet" "ops" {
  name                            = "snet-lw-ops"
  resource_group_name             = azurerm_resource_group.tier.name
  virtual_network_name            = azurerm_virtual_network.tier.name
  address_prefixes                = [local.subnets.ops]
  default_outbound_access_enabled = false

  delegation {
    name = "aci"
    service_delegation {
      name = "Microsoft.ContainerInstance/containerGroups"
    }
  }
}

resource "azurerm_subnet_nat_gateway_association" "ops" {
  subnet_id      = azurerm_subnet.ops.id
  nat_gateway_id = azurerm_nat_gateway.tier.id
}

resource "azurerm_subnet" "bastion" {
  count                = var.deployBastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.tier.name
  virtual_network_name = azurerm_virtual_network.tier.name
  address_prefixes     = [local.subnets.bastion]
}

resource "azurerm_virtual_network_peering" "to_spoke" {
  name                         = "peer-${local.base}-liquidware-to-spoke"
  resource_group_name          = azurerm_resource_group.tier.name
  virtual_network_name         = azurerm_virtual_network.tier.name
  remote_virtual_network_id    = var.spokeVnetId
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
