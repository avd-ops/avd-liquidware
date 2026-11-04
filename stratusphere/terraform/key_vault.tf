# Key Vault: holds the appliance credential Azure sets at deployment, so no one has to remember it.
# RBAC-authorized and purge-protected; the deployer (or a named group) gets Key Vault Secrets User.

locals {
  key_vault_secrets_user_role_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
}

resource "azurerm_key_vault" "this" {
  name                            = local.key_vault_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.this.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  rbac_authorization_enabled      = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false
  tags                            = local.all_tags
}

resource "azurerm_role_assignment" "key_vault_reader" {
  scope              = azurerm_key_vault.this.id
  role_definition_id = local.key_vault_secrets_user_role_id
  principal_id       = var.keyVaultReaderObjectId
  principal_type     = var.keyVaultReaderPrincipalType
}

resource "azurerm_key_vault_secret" "admin_username" {
  name         = "appliance-admin-username"
  value        = var.adminUsername
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "appliance-admin-password"
  value        = var.adminPassword
  content_type = "Local administrator Azure set on the Stratusphere appliances"
  key_vault_id = azurerm_key_vault.this.id
}
