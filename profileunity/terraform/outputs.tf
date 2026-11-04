# Outputs matching profileunity/bicep/main.bicep. Never output passwords or secrets.

output "resourceGroupName" {
  value = azurerm_resource_group.tier.name
}

output "vnetId" {
  value = azurerm_virtual_network.tier.id
}

output "keyVaultName" {
  value = azurerm_key_vault.tier.name
}

output "configAccountName" {
  value = azurerm_storage_account.config.name
}

output "packagesAccountName" {
  value = azurerm_storage_account.packages.name
}

output "opsIdentityId" {
  value = azurerm_user_assigned_identity.ops.id
}

output "mediaAccountName" {
  value = azurerm_storage_account.media.name
}

output "mediaBlobEndpoint" {
  value = azurerm_storage_account.media.primary_blob_endpoint
}

output "consoleVmName" {
  value = local.console_vm_name
}

output "packagingVmName" {
  value = local.packaging_vm_name
}
