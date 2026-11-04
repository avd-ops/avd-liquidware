# Assessment VNet: one subnet for the Stratusphere appliances, an optional AzureBastionSubnet, and
# an optional two-way peering to the network the endpoints live in. The NSG admits only what
# Stratusphere needs: TCP 443 (Connector ID Key callbacks and the web console), TCP 22 from Bastion,
# and TCP 5432 between the appliances when there is a Database or Collectors.
# Egress is explicit: the subnet has default outbound access off and leaves through a NAT Gateway.

locals {
  peer_parts          = local.peer ? split("/", var.peerVirtualNetworkResourceId) : []
  peer_resource_group = local.peer ? local.peer_parts[4] : ""
  peer_vnet_name      = local.peer ? local.peer_parts[8] : ""
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-ng-${local.vnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  # The appliance is regional; omitting availability zones works in regions without zones (lesson 0001).
  zones = []
  tags  = local.all_tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "ng-${local.vnet_name}"
  location                = var.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  zones                   = []
  tags                    = local.all_tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_network_security_group" "hub" {
  name                = "nsg-${local.vnet_name}-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.all_tags

  security_rule {
    name     = "Allow-Https-Callbacks-And-Console"
    priority = 100
    direction = "Inbound"
    access    = "Allow"
    protocol  = "Tcp"
    # Azure rejects service tags like 'VirtualNetwork' in plural source_address_prefixes.
    source_address_prefix      = length(var.callbackSourcePrefixes) == 1 ? var.callbackSourcePrefixes[0] : null
    source_address_prefixes    = length(var.callbackSourcePrefixes) > 1 ? var.callbackSourcePrefixes : null
    source_port_range          = "*"
    destination_address_prefix = var.hubSubnetPrefix
    destination_port_range     = "443"
  }

  dynamic "security_rule" {
    for_each = var.deployBastion ? [1] : []
    content {
      name                       = "Allow-Ssh-From-Bastion"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = var.bastionSubnetPrefix
      source_port_range          = "*"
      destination_address_prefix = var.hubSubnetPrefix
      destination_port_range     = "22"
    }
  }

  dynamic "security_rule" {
    for_each = local.allow_postgres ? [1] : []
    content {
      name                       = "Allow-Postgres-Between-Appliances"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = var.hubSubnetPrefix
      source_port_range          = "*"
      destination_address_prefix = var.hubSubnetPrefix
      destination_port_range     = "5432"
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
}

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.addressPrefix]
  tags                = local.all_tags
}

resource "azurerm_subnet" "hub" {
  name                            = "snet-stratusphere"
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.hubSubnetPrefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "hub" {
  subnet_id                 = azurerm_subnet.hub.id
  network_security_group_id = azurerm_network_security_group.hub.id
}

resource "azurerm_subnet_nat_gateway_association" "hub" {
  subnet_id      = azurerm_subnet.hub.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_subnet" "bastion" {
  count                = var.deployBastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.bastionSubnetPrefix]
}

resource "azurerm_virtual_network_peering" "to_peer" {
  count                        = local.peer ? 1 : 0
  name                         = "peer-${var.namePrefix}-stratusphere-to-${local.peer_vnet_name}"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.peerVirtualNetworkResourceId
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "from_peer" {
  count                        = local.peer ? 1 : 0
  name                         = "peer-${local.peer_vnet_name}-to-${var.namePrefix}-stratusphere"
  resource_group_name          = local.peer_resource_group
  virtual_network_name         = local.peer_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_public_ip" "bastion" {
  count               = var.deployBastion ? 1 : 0
  name                = "pip-${local.bastion_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.all_tags
}

resource "azurerm_bastion_host" "this" {
  count               = var.deployBastion ? 1 : 0
  name                = local.bastion_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"
  tags                = local.all_tags

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
