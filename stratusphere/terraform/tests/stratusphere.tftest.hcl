# Plan-only Terraform tests with mocked azurerm provider (offline, no tenant).
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      object_id       = "00000000-0000-0000-0000-000000000001"
    }
  }
}

variables {
  namePrefix             = "ssux"
  location               = "eastus2"
  hubImagePlan           = "stratusphere-hub"
  adminPassword          = "Placeholder-only-for-build-1!"
  keyVaultReaderObjectId = "00000000-0000-0000-0000-000000000001"
}

run "hub_only_defaults" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-ssux-stratusphere"
    error_message = "Expected resource group rg-ssux-stratusphere."
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.appliance) == 1 && azurerm_linux_virtual_machine.appliance["hub"].plan[0].name == "stratusphere-hub"
    error_message = "Expected Hub VM with matching Marketplace plan block."
  }

  assert {
    condition     = azurerm_subnet.hub.default_outbound_access_enabled == false && length(azurerm_public_ip.nat.zones) == 0
    error_message = "Hub subnet must have default outbound access off and regional NAT Gateway IP."
  }
}

run "database_and_collectors_enable_postgres" {
  command = plan

  variables {
    deployDatabase     = true
    databaseImagePlan  = "db-plan"
    collectorCount     = 2
    collectorImagePlan = "col-plan"
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.appliance) == 4
    error_message = "Expected Hub, Database, and 2 Collectors."
  }

  assert {
    condition     = length([for r in azurerm_network_security_group.hub.security_rule : r if r.name == "Allow-Postgres-Between-Appliances"]) == 1
    error_message = "Expected Allow-Postgres-Between-Appliances rule when Database or Collectors are deployed."
  }
}
