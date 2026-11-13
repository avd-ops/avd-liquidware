#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Deploy-LiquidwareTier.ps1 run end to end with every Az cmdlet mocked: what Cleanup removes,
# and that an unbuilt action or a declined confirmation changes nothing. Offline; no Az modules.

BeforeAll {
  $script:entry = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Deploy-LiquidwareTier.ps1'
  $sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
  $global:LwTest = @{
    Sub      = $sub
    TierVnet = "$sub/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev-liquidware"
    HubVnet  = "$sub/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    Removed  = $false
  }
  # Empty Az modules on PSModulePath, so the script's module checks and imports work unmocked.
  $script:modulePath = $env:PSModulePath
  foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.Compute', 'Az.KeyVault', 'Az.PrivateDns') {
    $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive "modules/$m") -Force
    Set-Content -Path (Join-Path $dir "$m.psm1") -Value '# test stand-in'
  }
  $env:PSModulePath = (Join-Path $TestDrive 'modules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
  # Stand-ins for the Az cmdlets the script calls (and Install-Module, absent where PowerShellGet
  # is), so Pester can mock them without the modules.
  foreach ($c in 'Get-AzContext', 'Set-AzContext', 'Get-AzResourceGroup', 'Get-AzResource', 'Get-AzVirtualNetwork', 'Get-AzPrivateDnsZone',
    'Get-AzPrivateDnsVirtualNetworkLink', 'Remove-AzVirtualNetworkPeering', 'Remove-AzPrivateDnsVirtualNetworkLink', 'Remove-AzResourceGroup',
    'Remove-AzVMRunCommand', 'Remove-AzResource', 'Remove-AzRoleAssignment', 'Get-AzVM', 'Start-AzVM', 'Get-AzADServicePrincipal', 'Get-AzADUser',
    'Get-AzKeyVault', 'New-AzSubscriptionDeployment', 'Get-AzSubscriptionDeploymentWhatIfResult', 'Get-AzRoleAssignment', 'Install-Module',
    'Sync-LiquidwareHosts.ps1', 'Publish-ProfileUnityConfig.ps1', 'Set-FlexAppAssignment.ps1',
    'Test-StratusphereReadiness.ps1', 'Deploy-Stratusphere.ps1', 'Deploy-CidKey.ps1') {
    # One superset of the parameters the script passes, so mocks' parameter filters can read them.
    New-Item -Path "function:global:$c" -Value {
      param($Name, $VirtualNetworkName, $ResourceGroupName, $ResourceId, $ZoneName, $Location, $Scope, $ResourceType, $SubscriptionId,
        $TemplateFile, $TemplateParameterObject, $VMName, $RunCommandName, $ObjectId, $RoleDefinitionName, $ApplicationId,
        $NamePrefix, $Environment, $Component, $Action, $ReportDirectory, $ConfigName, $Promote, $Ring, $StagedIniSha256, $ExportPath,
        $App, $Version, $PeerVnetId, $HostPoolName, $HostPoolResourceGroup, $Engine, $OutputPath, $HubAddress, $InstallerUrl, $InstallerSha256,
        [switch] $Status, [switch] $InRemovedState, [switch] $SignedIn, [switch] $NoBastion, [switch] $Fix, [switch] $DiscardLastCopy,
        [switch] $Force, [switch] $WhatIf, [Parameter(ValueFromRemainingArguments)] $Rest)
    } -Force | Out-Null
  }
}

AfterAll {
  $env:PSModulePath = $script:modulePath
  Remove-Variable -Name LwTest -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Deploy-LiquidwareTier.ps1 -Action Cleanup' {
  BeforeEach {
    $global:LwTest.Removed = $false
    Mock Install-Module { }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sandbox'; Id = '00000000-0000-0000-0000-000000000000' } } }
    Mock Get-AzResourceGroup {
      $g = @('rg-avdlz-dev-network', 'rg-avdlz-dev-management', 'rg-avdlz-dev-storage', 'rg-avdlz-dev-avd', 'rg-avdlz-dev-hosts')
      if (-not $global:LwTest.Removed) { $g += 'rg-avdlz-dev-liquidware' }
      $g | ForEach-Object { [pscustomobject]@{ ResourceGroupName = $_ } }
    }
    Mock Get-AzResource { @() }
    Mock Get-AzRoleAssignment { @() }
    Mock Get-AzVirtualNetwork {
      $peerings = @([pscustomobject]@{ Name = 'peer-avdlz-dev-to-hub'; RemoteVirtualNetwork = [pscustomobject]@{ Id = $global:LwTest.HubVnet } })
      if (-not $global:LwTest.Removed) { $peerings += [pscustomobject]@{ Name = 'peer-avdlz-dev-to-liquidware'; RemoteVirtualNetwork = [pscustomobject]@{ Id = $global:LwTest.TierVnet } } }
      [pscustomobject]@{ Id = '/x/vnet-avdlz-dev'; Location = 'centralus'; AddressSpace = [pscustomobject]@{ AddressPrefixes = @('10.100.0.0/22') }; Subnets = @(); VirtualNetworkPeerings = $peerings }
    }
    Mock Get-AzPrivateDnsZone { @([pscustomobject]@{ Name = 'privatelink.file.core.windows.net' }, [pscustomobject]@{ Name = 'privatelink.vaultcore.azure.net' }) }
    Mock Get-AzPrivateDnsVirtualNetworkLink {
      $l = @([pscustomobject]@{ Name = 'link-avdlz-dev'; VirtualNetworkId = '/x/vnet-avdlz-dev'; ResourceId = "/x/$ZoneName/link-avdlz-dev" })
      if (-not $global:LwTest.Removed) { $l += [pscustomobject]@{ Name = 'link-avdlz-dev-liquidware'; VirtualNetworkId = $global:LwTest.TierVnet; ResourceId = "/x/$ZoneName/link-avdlz-dev-liquidware" } }
      $l
    }
    Mock Remove-AzVirtualNetworkPeering { }
    Mock Remove-AzPrivateDnsVirtualNetworkLink { }
    Mock Remove-AzVMRunCommand { }
    Mock Remove-AzResource { }
    Mock Remove-AzRoleAssignment { }
    Mock Remove-AzResourceGroup { $global:LwTest.Removed = $true; $true }
    Mock Sync-LiquidwareHosts.ps1 { $global:LASTEXITCODE = 0 }
    Mock New-AzSubscriptionDeployment { }
    Mock Read-Host { 'rg-avdlz-dev-liquidware' }
    Mock Write-Host { }
  }

  It 'removes only the tier peering, the two tier DNS links and the tier resource group, then passes the teardown check' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -DiscardLastCopy
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 1 -Exactly -ParameterFilter { $Name -eq 'peer-avdlz-dev-to-liquidware' -and $VirtualNetworkName -eq 'vnet-avdlz-dev' -and $ResourceGroupName -eq 'rg-avdlz-dev-network' }
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 1 -Exactly
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 2 -Exactly -ParameterFilter { $ResourceId -like '*/link-avdlz-dev-liquidware' }
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 2 -Exactly
    Should -Invoke Remove-AzResourceGroup -Times 1 -Exactly -ParameterFilter { $Name -eq 'rg-avdlz-dev-liquidware' }
    Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'PASS\s+teardown' }
    Should -Invoke New-AzSubscriptionDeployment -Times 0
    $report = Get-ChildItem $TestDrive -Filter 'cleanup-avdlz-dev-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    ($report.results | Where-Object check -eq 'teardown').status | Should -Be 'PASS'
  }

  It 'drains/uninstalls session host Run Commands, removes DCR associations, host role assignments and portability share with -RemoveUserData' {
    Mock Get-AzResource {
      if ($global:LwTest.Removed) { return @() }
      if ($ResourceGroupName -eq 'rg-avdlz-dev-hosts') {
        return @(
          [pscustomobject]@{ Name = 'vm-sh0/lw-profileunity-client'; ResourceType = 'Microsoft.Compute/virtualMachines/runCommands'; ResourceGroupName = 'rg-avdlz-dev-hosts'; ResourceId = '/x/vm-sh0/runCommands/lw-profileunity-client' }
          [pscustomobject]@{ Name = 'vm-sh0/lw-restrictions'; ResourceType = 'Microsoft.Insights/dataCollectionRuleAssociations'; ResourceGroupName = 'rg-avdlz-dev-hosts'; ResourceId = '/x/vm-sh0/dcr/lw-restrictions' }
        )
      }
      if ($ResourceGroupName -eq 'rg-avdlz-dev-storage') {
        return @(
          [pscustomobject]@{ Name = 'stavdlzdevabc123/default/portability'; ResourceType = 'Microsoft.Storage/storageAccounts/fileServices/shares'; ResourceGroupName = 'rg-avdlz-dev-storage'; ResourceId = '/x/stavdlzdevabc123/fileServices/default/shares/portability' }
        )
      }
      @()
    }
    Mock Get-AzRoleAssignment {
      if ($global:LwTest.Removed) { return @() }
      @([pscustomobject]@{ ObjectId = 'sp-host0'; ObjectType = 'ServicePrincipal'; RoleDefinitionName = 'Storage File Data SMB Share Reader'; RoleAssignmentId = '/x/ra0'; Scope = '/x/stlwconfig' })
    }
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -RemoveUserData -DiscardLastCopy -Force
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Sync-LiquidwareHosts.ps1 -Times 1 -Exactly -ParameterFilter { $Component -eq 'ProfileUnity' -and $Action -eq 'Cleanup' }
    Should -Invoke Remove-AzVMRunCommand -Times 1 -Exactly -ParameterFilter { $VMName -eq 'vm-sh0' -and $RunCommandName -eq 'lw-profileunity-client' }
    Should -Invoke Remove-AzResource -Times 1 -Exactly -ParameterFilter { $ResourceId -eq '/x/vm-sh0/dcr/lw-restrictions' }
    Should -Invoke Remove-AzRoleAssignment -Times 1 -Exactly -ParameterFilter { $ObjectId -eq 'sp-host0' -and $RoleDefinitionName -eq 'Storage File Data SMB Share Reader' }
    Should -Invoke Remove-AzResource -Times 1 -Exactly -ParameterFilter { $ResourceId -eq '/x/stavdlzdevabc123/fileServices/default/shares/portability' }
    Should -Invoke Remove-AzResourceGroup -Times 1 -Exactly -ParameterFilter { $Name -eq 'rg-avdlz-dev-liquidware' }
  }

  It 'removes nothing without -DiscardLastCopy, and does not ask (never delete the last copy)' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive
    $LASTEXITCODE | Should -Be 1
    Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'FAIL\s+last-copy' }
    Should -Invoke Read-Host -Times 0
    Should -Invoke Remove-AzResourceGroup -Times 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 0
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 0
  }

  It 'removes nothing when the operator does not type the resource group name' {
    Mock Read-Host { 'no' }
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -DiscardLastCopy
    Should -Invoke Write-Host -Times 4 -Exactly -ParameterFilter { "$Object" -match 'INFO\s+cleanup-step' }
    Should -Invoke Remove-AzResourceGroup -Times 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 0
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 0
  }

  It 'removes nothing with -WhatIf, and does not ask' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -WhatIf
    Should -Invoke Write-Host -Times 4 -Exactly -ParameterFilter { "$Object" -match 'INFO\s+cleanup-step' }
    Should -Invoke Remove-AzResourceGroup -Times 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 0
    Should -Invoke Read-Host -Times 0
  }

  It 'fails an action that is not built before reading or changing anything' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component Stratusphere -Action Promote -ReportDirectory $TestDrive
    $LASTEXITCODE | Should -Be 1
    Should -Invoke Get-AzResourceGroup -Times 0
    Should -Invoke Remove-AzResourceGroup -Times 0
  }
}

Describe 'Deploy-LiquidwareTier.ps1 dispatch for Configure, Promote, Fix, Plan and Stratusphere' {
  BeforeEach {
    $fixture = Get-Content (Join-Path $PSScriptRoot 'fixtures/landing-zone-dev.json') -Raw | ConvertFrom-Json
    Mock Install-Module { }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sandbox'; Id = '00000000-0000-0000-0000-000000000000' } } }
    Mock Get-AzResourceGroup {
      @($fixture.ResourceGroup + 'rg-avdlz-dev-liquidware') | ForEach-Object { [pscustomobject]@{ ResourceGroupName = $_ } }
    }
    Mock Get-AzResource {
      @($fixture.Resource | Where-Object { -not $ResourceGroupName -or $_.ResourceGroupName -eq $ResourceGroupName })
    }
    Mock Get-AzVirtualNetwork {
      [pscustomobject]@{
        Id                     = $fixture.Vnet.Id
        Location               = $fixture.Vnet.Location
        AddressSpace           = [pscustomobject]@{ AddressPrefixes = @($fixture.Vnet.AddressPrefixes) }
        Subnets                = @($fixture.Vnet.Subnets | ForEach-Object { [pscustomobject]@{ Name = $_.Name; AddressPrefix = @($_.AddressPrefix); NatGateway = $(if ($_.NatGatewayId) { [pscustomobject]@{ Id = $_.NatGatewayId } } else { $null }); RouteTable = $null } })
        VirtualNetworkPeerings = @()
      }
    }
    Mock Get-AzRoleAssignment {
      @([pscustomobject]@{ ObjectId = '00000000-0000-0000-0000-000000000011'; ObjectType = 'Group'; RoleDefinitionName = 'Storage File Data SMB Share Contributor' })
    }
    Mock Get-AzADServicePrincipal { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000022' } }
    Mock Get-AzADUser { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000033' } }
    Mock Get-AzKeyVault { @() }
    Mock Get-AzVM { [pscustomobject]@{ Name = 'vm-avdlzlwcon'; Identity = [pscustomobject]@{ PrincipalId = '00000000-0000-0000-0000-000000000044' }; Statuses = @([pscustomobject]@{ Code = 'PowerState/running' }) } }
    Mock Start-AzVM { }
    Mock Get-AzSubscriptionDeploymentWhatIfResult { [pscustomobject]@{ Changes = @() } }
    Mock New-AzSubscriptionDeployment { [pscustomobject]@{ ProvisioningState = 'Succeeded'; Outputs = @{ mediaAccountName = @{ Value = 'stlwmedia' } } } }
    Mock Sync-LiquidwareHosts.ps1 { $global:LASTEXITCODE = 0 }
    Mock Publish-ProfileUnityConfig.ps1 { $global:LASTEXITCODE = 0 }
    Mock Set-FlexAppAssignment.ps1 { $global:LASTEXITCODE = 0 }
    Mock Test-StratusphereReadiness.ps1 { $global:LASTEXITCODE = 0 }
    Mock Deploy-Stratusphere.ps1 { $global:LASTEXITCODE = 0 }
    Mock Deploy-CidKey.ps1 { $global:LASTEXITCODE = 0 }
    Mock Write-Host { }
  }

  It 'dispatches -Action Configure to Sync-LiquidwareHosts.ps1 for ProfileUnity/FlexApp and Deploy-CidKey.ps1 for Stratusphere' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity, FlexApp, Stratusphere -Action Configure -ReportDirectory $TestDrive -Force
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Sync-LiquidwareHosts.ps1 -Times 1 -Exactly -ParameterFilter { $Component -eq 'ProfileUnity' -and $Action -eq 'Configure' }
    Should -Invoke Deploy-CidKey.ps1 -Times 1 -Exactly -ParameterFilter { $HostPoolName -eq 'vdpool-avdlz-dev' -and $HostPoolResourceGroup -eq 'rg-avdlz-dev-avd' -and $Action -eq 'Install' }
  }

  It 'dispatches -Action Promote to Publish-ProfileUnityConfig.ps1 and Set-FlexAppAssignment.ps1 with -Ring' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity, FlexApp -Action Promote -Ring All -ConfigName default -App notepadpp -Version 8.6.0 -ReportDirectory $TestDrive -Force
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Publish-ProfileUnityConfig.ps1 -Times 1 -Exactly -ParameterFilter { $ConfigName -eq 'default' -and $Ring -eq 'All' }
    Should -Invoke Set-FlexAppAssignment.ps1 -Times 1 -Exactly -ParameterFilter { $App -eq 'notepadpp' -and $Version -eq '8.6.0' -and $Ring -eq 'All' }
  }

  It 'dispatches -Action Fix to start a stopped console VM, repair failed hosts and redeploy drifted resources' {
    Mock Get-AzVM { [pscustomobject]@{ Name = 'vm-avdlzlwcon'; Identity = [pscustomobject]@{ PrincipalId = '00000000-0000-0000-0000-000000000044' }; Statuses = @([pscustomobject]@{ Code = 'PowerState/deallocated' }) } }
    Mock Sync-LiquidwareHosts.ps1 {
      if ($Action -eq 'Check') { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
    }
    Mock Get-AzSubscriptionDeploymentWhatIfResult {
      [pscustomobject]@{ Changes = @([pscustomobject]@{ ChangeType = 'Modify'; FullyQualifiedResourceId = '/subscriptions/0/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.Network/natGateways/nat-avdlz-dev-liquidware' }) }
    }
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Fix -Engine Bicep -ReportDirectory $TestDrive -Force
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Start-AzVM -Times 1 -Exactly -ParameterFilter { $Name -eq 'vm-avdlzlwcon' }
    Should -Invoke Sync-LiquidwareHosts.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Check' }
    Should -Invoke Sync-LiquidwareHosts.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Configure' }
    Should -Invoke New-AzSubscriptionDeployment -Times 1 -Exactly
  }

  It 'dispatches -Component Stratusphere across Plan, Check, Deploy, Fix and Cleanup with -Engine' {
    foreach ($act in 'Plan', 'Check', 'Deploy', 'Fix') {
      & $script:entry -NamePrefix avdlz -Environment dev -Component Stratusphere -Action $act -Engine Terraform -ReportDirectory $TestDrive -Force
      $LASTEXITCODE | Should -Be 0
    }
    Should -Invoke Test-StratusphereReadiness.ps1 -Times 4 -Exactly -ParameterFilter { $Location -eq 'centralus' -and $NamePrefix -eq 'avdlzd' -and $Engine -eq 'Terraform' }
    Should -Invoke Deploy-Stratusphere.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Plan' -and $Engine -eq 'Terraform' }
    Should -Invoke Deploy-Stratusphere.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Check' -and $Engine -eq 'Terraform' }
    Should -Invoke Deploy-Stratusphere.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Deploy' -and $Engine -eq 'Terraform' }
    Should -Invoke Deploy-Stratusphere.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Fix' -and $Engine -eq 'Terraform' }

    & $script:entry -NamePrefix avdlz -Environment dev -Component Stratusphere -Action Cleanup -Engine Terraform -ReportDirectory $TestDrive -DiscardLastCopy -Force
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Deploy-CidKey.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Cleanup' -and $HostPoolName -eq 'vdpool-avdlz-dev' }
    Should -Invoke Deploy-Stratusphere.ps1 -Times 1 -Exactly -ParameterFilter { $Action -eq 'Cleanup' -and $Engine -eq 'Terraform' }
  }

  It 'surfaces Get-LwCostEstimate lines and the budget warning during -Action Plan' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Plan -Engine Bicep -ReportDirectory $TestDrive
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'INFO\s+cost-estimate' }
    Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'WARN\s+budget' }
  }
}
