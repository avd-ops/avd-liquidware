#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Guards on the Stratusphere Terraform configuration.

BeforeAll {
  $script:bicep = (Get-Command bicep -ErrorAction Stop).Source
  $script:root = Split-Path $PSScriptRoot -Parent
  $script:tfDir = Join-Path $script:root 'terraform'
  $env:SSUX_ADMIN_PASSWORD = 'Placeholder-only-for-build-1!'
  $env:SSUX_KV_READER_ID = '00000000-0000-0000-0000-000000000001'
  function Get-Compiled {
    $raw = & $script:bicep build-params (Join-Path $script:root 'parameters/lab.bicepparam') --stdout 2>&1
    if ($LASTEXITCODE -ne 0) { throw "bicep build-params failed: $raw" }
    ($raw -join "`n") | ConvertFrom-Json -Depth 100
  }
  $script:compiled = Get-Compiled
  $script:bicepTemplate = $script:compiled.templateJson | ConvertFrom-Json -Depth 100 -AsHashtable
  $script:tfFiles = Get-ChildItem -Path $script:tfDir -Filter '*.tf' | Sort-Object Name
  $script:tfAll = ($script:tfFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $script:tfVariables = Get-Content (Join-Path $script:tfDir 'variables.tf') -Raw
  $script:tfMain = Get-Content (Join-Path $script:tfDir 'main.tf') -Raw
  $script:tfNetwork = Get-Content (Join-Path $script:tfDir 'network.tf') -Raw
  $script:tfKeyVault = Get-Content (Join-Path $script:tfDir 'key_vault.tf') -Raw
  $script:tfAppliances = Get-Content (Join-Path $script:tfDir 'appliances.tf') -Raw
  $script:tfOutputs = Get-Content (Join-Path $script:tfDir 'outputs.tf') -Raw
  Import-Module (Join-Path $script:root 'scripts/ops/StratusphereAppliance.psm1') -Force
}

Describe 'Stratusphere Terraform parity with Bicep' {
  It 'declares every Bicep parameter in variables.tf' {
    $bicepParams = @($script:bicepTemplate['parameters'].Keys | Sort-Object)
    $tfVars = @([regex]::Matches($script:tfVariables, '(?m)^variable\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    $tfVars | Should -Be $bicepParams
  }

  It 'declares every Bicep output in outputs.tf' {
    $bicepOutputs = @($script:bicepTemplate['outputs'].Keys | Sort-Object)
    $tfOutNames = @([regex]::Matches($script:tfOutputs, '(?m)^output\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    $tfOutNames | Should -Be $bicepOutputs
  }

  It 'marks adminPassword as sensitive' {
    $script:tfVariables | Should -Match '(?s)variable\s+"adminPassword"\s*\{[^}]*sensitive\s*=\s*true'
  }
}

Describe 'Marketplace image (Terraform)' {
  It 'sends a plan block that matches the source_image_reference' {
    $script:tfAppliances | Should -Match '(?s)plan\s*\{\s*name\s*=\s*each\.value\.image_plan\s*publisher\s*=\s*var\.imagePublisher\s*product\s*=\s*var\.imageOffer\s*\}'
    $script:tfAppliances | Should -Match '(?s)source_image_reference\s*\{\s*publisher\s*=\s*var\.imagePublisher\s*offer\s*=\s*var\.imageOffer\s*sku\s*=\s*each\.value\.image_plan\s*version\s*=\s*var\.imageVersion\s*\}'
  }
}

Describe 'Roles (Terraform)' {
  It 'Get-SsuxTerraformVariable takes Database and Collectors from Target, off by default' {
    $defaultTarget = Get-SsuxDeployTarget -Role @('Hub') -Plan @{ Hub = 'hub-plan' }
    $defaultVars = Get-SsuxTerraformVariable -Location 'eastus2' -NamePrefix 'ssux' -Target $defaultTarget -KeyVaultReaderObjectId '00000000-0000-0000-0000-000000000001'
    $defaultVars.deployDatabase | Should -BeFalse
    $defaultVars.collectorCount | Should -Be 0
    $defaultVars.hubImagePlan | Should -Be 'hub-plan'

    $roleTarget = Get-SsuxDeployTarget -Role @('Hub', 'Database', 'Collector') -CollectorCount 2 -Plan @{ Hub = 'hub-plan'; Database = 'db-plan'; Collector = 'col-plan' }
    $roleVars = Get-SsuxTerraformVariable -Location 'eastus2' -NamePrefix 'ssux' -Target $roleTarget -KeyVaultReaderObjectId '00000000-0000-0000-0000-000000000001'
    $roleVars.deployDatabase | Should -BeTrue
    $roleVars.collectorCount | Should -Be 2
    $roleVars.databaseImagePlan | Should -Be 'db-plan'
    $roleVars.collectorImagePlan | Should -Be 'col-plan'
  }

  It 'deploys every role through the unified appliance resource so each gets the plan block' {
    $script:tfAppliances | Should -Match 'resource\s+"azurerm_linux_virtual_machine"\s+"appliance"'
    $script:tfAppliances | Should -Match 'for_each\s*=\s*local\.appliance_definitions'
    $script:tfAppliances | Should -Match 'image_plan\s*=\s*var\.hubImagePlan'
    $script:tfAppliances | Should -Match 'image_plan\s*=\s*var\.databaseImagePlan'
    $script:tfAppliances | Should -Match 'image_plan\s*=\s*var\.collectorImagePlan'
  }

  It 'uses the names, IPs and address space the scripts expect' {
    $d = Get-SsuxApplianceDefault
    $script:tfVariables | Should -Match ([regex]::Escape("default     = `"$($d.Ip.Hub)`""))
    $script:tfVariables | Should -Match ([regex]::Escape("default     = `"$($d.Ip.Database)`""))
    foreach ($ip in $d.CollectorIps) {
      $script:tfVariables | Should -Match ([regex]::Escape("`"$ip`""))
    }
    $script:tfAppliances | Should -Match 'vm-\$\{var\.namePrefix\}-hub'
    $script:tfAppliances | Should -Match 'vm-\$\{var\.namePrefix\}-db'
    $script:tfAppliances | Should -Match 'vm-\$\{var\.namePrefix\}-col\$\{i \+ 1\}'
    $script:tfAppliances | Should -Match '"stratusphere-role"\s*=\s*each\.value\.role'
  }

  It 'configures a daily DevTestLab shutdown schedule on each appliance VM' {
    $script:tfAppliances | Should -Match 'resource\s+"azurerm_dev_test_global_vm_shutdown_schedule"\s+"appliance"'
    $script:tfAppliances | Should -Match 'virtual_machine_id\s*=\s*azurerm_linux_virtual_machine\.appliance\[each\.key\]\.id'
    $script:tfAppliances | Should -Match 'daily_recurrence_time\s*=\s*var\.autoShutdownTime'
  }
}

Describe 'Terraform variable builder' {
  It 'sets environment and stamps deadline tags when DeadlineConfig is provided' {
    $target = Get-SsuxDeployTarget -Role @('Hub') -Plan @{ Hub = 'example-plan' }
    $deadline = Get-SsuxSandboxDeadlineConfig -SubscriptionId '00000000-0000-0000-0000-000000000000' -NamePrefix 'ssux' -Environment 'dev' -BatchId 'b20261103-1800' -NowUtc ([datetime]'2026-11-03T18:00:00Z')
    $vars = Get-SsuxTerraformVariable -Location 'westus3' -NamePrefix 'ssux' -Environment 'dev' -Target $target -KeyVaultReaderObjectId '00000000-0000-0000-0000-000000000001' -DeadlineConfig $deadline
    $vars.location | Should -Be 'westus3'
    $vars.environment | Should -Be 'dev'
    $vars.hubImagePlan | Should -Be 'example-plan'
    $vars.tags['avdlz-component'] | Should -Be 'stratusphere-ux'
    $vars.tags['avdlz-shutdown-schedule'] | Should -Be $deadline.ShutdownScheduleName
    $vars.tags['avdlz-teardown-schedule'] | Should -Be $deadline.TeardownScheduleName
  }
}

Describe 'Hub network exposure (Terraform)' {
  It 'admits only TCP 443 and SSH from Bastion, then denies' {
    $script:tfNetwork | Should -Match 'name\s*=\s*"Allow-Https-Callbacks-And-Console"'
    $script:tfNetwork | Should -Match 'destination_port_range\s*=\s*"443"'
    $script:tfNetwork | Should -Match 'name\s*=\s*"Allow-Ssh-From-Bastion"'
    $script:tfNetwork | Should -Match 'destination_port_range\s*=\s*"22"'
    $script:tfNetwork | Should -Match 'name\s*=\s*"Deny-Other-Inbound"'
    $script:tfNetwork | Should -Not -Match '"Internet"'
  }

  It 'opens TCP 5432 only between appliances, and only with a Database or Collectors' {
    $script:tfMain | Should -Match 'allow_postgres\s*=\s*var\.deployDatabase\s*\|\|\s*var\.collectorCount\s*>\s*0'
    $script:tfNetwork | Should -Match '(?s)for_each\s*=\s*local\.allow_postgres\s*\?\s*\[1\]\s*:\s*\[\].*?name\s*=\s*"Allow-Postgres-Between-Appliances".*?source_address_prefix\s*=\s*var\.hubSubnetPrefix.*?destination_address_prefix\s*=\s*var\.hubSubnetPrefix.*?destination_port_range\s*=\s*"5432"'
  }

  It 'uses singular source_address_prefix when callbackSourcePrefixes has one entry so VirtualNetwork service tag passes ARM preflight' {
    $script:tfNetwork | Should -Match 'source_address_prefix\s*=\s*length\(var\.callbackSourcePrefixes\)\s*==\s*1\s*\?\s*var\.callbackSourcePrefixes\[0\]\s*:\s*null'
    $script:tfNetwork | Should -Match 'source_address_prefixes\s*=\s*length\(var\.callbackSourcePrefixes\)\s*>\s*1\s*\?\s*var\.callbackSourcePrefixes\s*:\s*null'
  }
}

Describe 'Egress (Terraform)' {
  It 'turns default outbound access off and sends the Hub subnet through a regional NAT Gateway' {
    $script:tfNetwork | Should -Match 'default_outbound_access_enabled\s*=\s*false'
    $script:tfNetwork | Should -Match 'resource\s+"azurerm_subnet_nat_gateway_association"\s+"hub"'
    $script:tfNetwork | Should -Match '(?ms)^resource\s+"azurerm_public_ip"\s+"nat"\s*\{.*?zones\s*=\s*\[\].*?^\}'
  }
}

Describe 'Disclaimer (Terraform)' {
  It 'is at the top of terraform/main.tf' {
    (Get-Content (Join-Path $script:tfDir 'main.tf') -TotalCount 8) -join "`n" | Should -Match 'Personal project, not for production use'
    (Get-Content (Join-Path $script:tfDir 'main.tf') -TotalCount 8) -join "`n" | Should -Match 'Not affiliated with .*Liquidware'
  }
}
