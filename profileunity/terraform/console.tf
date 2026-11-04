# The ProfileUnity console VM and its least-privilege role assignments (deploy-spec sections 5 and 6.1).
# Deployed only when consoleExists is false: an existing VM keeps the password it was created with (lesson 0002).

resource "azurerm_key_vault_secret" "console_admin_password" {
  count        = var.consoleExists ? 0 : 1
  name         = "lw-console-password"
  value        = var.consoleAdminPassword
  content_type = "Local administrator lwadmin on ${local.console_vm_name}"
  key_vault_id = azurerm_key_vault.tier.id
}

resource "azurerm_network_interface" "console" {
  count               = var.consoleExists ? 0 : 1
  name                = "nic-${local.console_vm_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.tier.name
  tags                = local.all_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.console.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.console_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "console" {
  count                      = var.consoleExists ? 0 : 1
  name                       = local.console_vm_name
  computer_name              = local.console_computer_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.tier.name
  size                       = "Standard_D2as_v5"
  admin_username             = "lwadmin"
  admin_password             = var.consoleAdminPassword
  network_interface_ids      = [azurerm_network_interface.console[0].id]
  secure_boot_enabled        = true
  vtpm_enabled               = true
  encryption_at_host_enabled = true
  provision_vm_agent         = true
  enable_automatic_updates   = true
  patch_mode                 = "AutomaticByPlatform"
  tags                       = merge(local.all_tags, { "liquidware-role" = "console" })

  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  boot_diagnostics {}
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "console" {
  count                 = (!var.consoleExists && var.environment != "prod") ? 1 : 0
  virtual_machine_id    = azurerm_windows_virtual_machine.console[0].id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.autoShutdownTime
  timezone              = "UTC"
  tags                  = local.all_tags

  notification_settings {
    enabled = false
  }
}

# ---------- Console & operator access ----------

locals {
  effective_console_principal_id = var.consoleExists ? var.consolePrincipalId : azurerm_windows_virtual_machine.console[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "console_media" {
  scope              = azurerm_storage_container.media.resource_manager_id
  role_definition_id = local.role_definition_ids.blobDataReader
  principal_id       = local.effective_console_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "console_staging" {
  scope              = azurerm_storage_container.staging.resource_manager_id
  role_definition_id = local.role_definition_ids.blobDataContributor
  principal_id       = local.effective_console_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "console_license" {
  count              = var.licenseStored ? 1 : 0
  scope              = "${azurerm_key_vault.tier.id}/secrets/lw-licstr"
  role_definition_id = local.role_definition_ids.keyVaultSecretsUser
  principal_id       = local.effective_console_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_console_password" {
  scope              = "${azurerm_key_vault.tier.id}/secrets/lw-console-password"
  role_definition_id = local.role_definition_ids.keyVaultSecretsUser
  principal_id       = var.operatorObjectId
  principal_type     = "User"
}
