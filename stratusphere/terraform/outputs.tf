# Outputs matching stratusphere/bicep/main.bicep.

output "resourceGroupName" {
  value = azurerm_resource_group.this.name
}

output "keyVaultName" {
  value = azurerm_key_vault.this.name
}

output "vnetResourceId" {
  value = azurerm_virtual_network.this.id
}

output "appliances" {
  value = concat(
    var.deployHub ? [{ role = "Hub", name = "vm-${var.namePrefix}-hub", privateIp = var.hubPrivateIp }] : [],
    var.deployDatabase ? [{ role = "Database", name = "vm-${var.namePrefix}-db", privateIp = var.databasePrivateIp }] : [],
    local.collector_rows
  )
}
