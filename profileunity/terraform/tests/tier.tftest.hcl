# Plan-only Terraform tests with mocked azurerm provider (offline, no tenant).
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      object_id       = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_data "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-storage/providers/Microsoft.Storage/storageAccounts/stavdlzdevabc123"
    }
  }
}

variables {
  location                         = "northcentralus"
  namePrefix                       = "avdlz"
  environment                      = "dev"
  tierAddressPrefix                = "10.61.0.0/24"
  spokeVnetId                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev"
  spokeAddressPrefixes             = ["10.100.0.0/22"]
  sessionHostSubnetPrefix          = "10.100.0.0/23"
  spokePrivateEndpointSubnetPrefix = "10.100.2.0/27"
  fileDnsZoneId                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  vaultDnsZoneId                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  usersGroupObjectId               = "33333333-3333-3333-3333-333333333333"
  avdServicePrincipalObjectIds     = ["44444444-4444-4444-4444-444444444444", "55555555-5555-5555-5555-555555555555"]
  operatorObjectId                 = "22222222-2222-2222-2222-222222222222"
  consoleAdminPassword             = "Placeholder-only-for-test-1!"
}

run "default_tier_plan" {
  command = plan

  assert {
    condition     = azurerm_resource_group.tier.name == "rg-avdlz-dev-liquidware"
    error_message = "Expected resource group rg-avdlz-dev-liquidware."
  }

  assert {
    condition     = azurerm_storage_account.config.shared_access_key_enabled == false && azurerm_storage_account.config.public_network_access_enabled == false
    error_message = "Live config account must have shared key off and public network access disabled."
  }

  assert {
    condition     = azurerm_storage_account.media.shared_access_key_enabled == false && azurerm_storage_account.media.default_to_oauth_authentication == true
    error_message = "Media account must have shared key off and default to OAuth."
  }

  assert {
    condition     = length(azurerm_windows_virtual_machine.console) == 1 && length(azurerm_windows_virtual_machine.packaging) == 0
    error_message = "Default plan should deploy the console VM and skip the on-demand packaging VM."
  }

  assert {
    condition     = azurerm_network_interface.console[0].ip_configuration[0].private_ip_address == "10.61.0.4"
    error_message = "Console static IP must be 10.61.0.4."
  }
}

run "existing_console_and_opt_in_features" {
  command = plan

  variables {
    consoleExists                 = true
    consolePrincipalId            = "66666666-6666-6666-6666-666666666666"
    licenseStored                 = true
    deployBastion                 = true
    enablePortability             = true
    profilesStorageAccountName    = "stavdlzdevabc123"
    profilesResourceGroupName     = "rg-avdlz-dev-storage"
    enableApplicationRestrictions = true
    logAnalyticsWorkspaceId       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-management/providers/Microsoft.OperationalInsights/workspaces/log-avdlz-dev"
    deployPackagingVm             = true
    packagingAdminPassword        = "Placeholder-only-for-pkg-1!"
    enableBackup                  = true
  }

  assert {
    condition     = length(azurerm_windows_virtual_machine.console) == 0 && length(azurerm_key_vault_secret.console_admin_password) == 0
    error_message = "When consoleExists is true, the console VM and its password secret must not be recreated."
  }

  assert {
    condition     = length(azurerm_role_assignment.console_license) == 1
    error_message = "When licenseStored is true, console_license role assignment must be created."
  }

  assert {
    condition     = length(azurerm_subnet.bastion) == 1 && length(azurerm_storage_share.portability) == 1 && length(azurerm_monitor_data_collection_rule.restrictions) == 1 && length(azurerm_windows_virtual_machine.packaging) == 1 && length(azurerm_recovery_services_vault.tier) == 1
    error_message = "All opt-in tier resources should be planned when enabled."
  }
}
