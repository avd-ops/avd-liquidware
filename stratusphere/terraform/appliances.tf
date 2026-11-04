# Stratusphere appliances (Hub, Database or Collector) from Azure Marketplace.
# Every role is created from the same resource definition so each gets a `plan` block that matches
# its `source_image_reference` and a static private IP.

locals {
  collector_rows = [
    for i in range(var.collectorCount) : {
      role      = "Collector"
      name      = "vm-${var.namePrefix}-col${i + 1}"
      privateIp = var.collectorPrivateIps[i]
    }
  ]

  appliance_definitions = merge(
    var.deployHub ? {
      "hub" = {
        role            = "hub"
        name            = "vm-${var.namePrefix}-hub"
        vm_size         = var.hubVmSize
        os_disk_size_gb = var.hubOsDiskSizeGB
        private_ip      = var.hubPrivateIp
        image_plan      = var.hubImagePlan
      }
    } : {},
    var.deployDatabase ? {
      "database" = {
        role            = "database"
        name            = "vm-${var.namePrefix}-db"
        vm_size         = var.databaseVmSize
        os_disk_size_gb = var.databaseOsDiskSizeGB
        private_ip      = var.databasePrivateIp
        image_plan      = var.databaseImagePlan
      }
    } : {},
    {
      for i in range(var.collectorCount) : "collector-${i + 1}" => {
        role            = "collector-${i + 1}"
        name            = "vm-${var.namePrefix}-col${i + 1}"
        vm_size         = var.collectorVmSize
        os_disk_size_gb = var.collectorOsDiskSizeGB
        private_ip      = var.collectorPrivateIps[i]
        image_plan      = var.collectorImagePlan
      }
    }
  )
}

resource "azurerm_network_interface" "appliance" {
  for_each            = local.appliance_definitions
  name                = "${each.value.name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = merge(local.all_tags, { "stratusphere-role" = each.value.role })

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.hub.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

resource "azurerm_linux_virtual_machine" "appliance" {
  for_each                        = local.appliance_definitions
  name                            = each.value.name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.this.name
  size                            = each.value.vm_size
  admin_username                  = var.adminUsername
  admin_password                  = var.adminPassword
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.appliance[each.key].id]
  tags                            = merge(local.all_tags, { "stratusphere-role" = each.value.role })

  source_image_reference {
    publisher = var.imagePublisher
    offer     = var.imageOffer
    sku       = each.value.image_plan
    version   = var.imageVersion
  }

  plan {
    name      = each.value.image_plan
    publisher = var.imagePublisher
    product   = var.imageOffer
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = each.value.os_disk_size_gb
  }

  boot_diagnostics {}
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "appliance" {
  for_each              = var.autoShutdownTime != "" ? local.appliance_definitions : {}
  virtual_machine_id    = azurerm_linux_virtual_machine.appliance[each.key].id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.autoShutdownTime
  timezone              = var.autoShutdownTimeZone
  tags                  = local.all_tags

  notification_settings {
    enabled = false
  }
}
