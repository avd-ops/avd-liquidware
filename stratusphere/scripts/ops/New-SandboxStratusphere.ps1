<#
.SYNOPSIS
  Deploys or plans the Stratusphere UX Hub with deadline auto-shutdown/auto-teardown and automatic VNet peering to a standalone Windows 11 test VM.
  Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  Wraps Deploy-Stratusphere.ps1 with ephemeral lab/sandbox defaults:
    - Names the resource group rg-<Name>-<Environment>-stratusphere (default: rg-ssux-dev-stratusphere)
      so Invoke-AvdSandboxDeadline in avdlz-runs-rg matches rg-<Name>-<Environment>-*.
    - Arms two OneTime schedules in aa-avdlz-runs before deploying any billable resource:
        G1 (Deallocate) at +ShutdownAfterMinutes (default 120 minutes)
        G2 (Delete)     at +TeardownAfterMinutes (default 240 minutes)
    - Stamps avdlz-component, avdlz-owner, avdlz-purpose, avdlz-shutdown-utc, avdlz-teardown-utc,
      avdlz-shutdown-schedule, and avdlz-teardown-schedule tags on the resource group and resources.
    - Attaches a daily 20:00 Central Standard Time Microsoft.DevTestLab/schedules shutdown task
      (shutdown-computevm-vm-<Name>-hub) as belt-and-suspenders protection.
    - Automatically discovers a standalone test VM VNet matching rg-<TestVmName>-<Environment>-vm /
      vnet-<TestVmName>-vm (or any rg-*-<Environment>-vm in the subscription when -TestVmName is omitted),
      adopts its region when -Location is not explicitly passed, and peers vnet-<Name>-stratusphere
      (10.60.0.0/24) with it both ways.

.EXAMPLE
  ./scripts/ops/New-SandboxStratusphere.ps1 -Action Plan
.EXAMPLE
  ./scripts/ops/New-SandboxStratusphere.ps1 -Action Deploy -ShutdownAfterMinutes 120 -TeardownAfterMinutes 240
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('Plan', 'Deploy', 'Check', 'Fix')] [string] $Action = 'Plan',
  [Alias('NamePrefix')] [ValidatePattern('^[a-z0-9]{2,8}$')] [string] $Name = 'ssux',
  [ValidateSet('dev', 'test', 'prod')] [string] $Environment = 'dev',
  [string] $Location = 'centralus',
  [string] $HubPlan = '670-2-hub',
  [string] $HubVmSize = 'Standard_D4as_v6',
  [ValidatePattern('^([a-z0-9]{2,8})?$')] [string] $TestVmName = '',
  [string] $PeerVnetId = '',
  [ValidateRange(6, 1440)] [int] $ShutdownAfterMinutes = 120,
  [ValidateRange(6, 1440)] [int] $TeardownAfterMinutes = 240,
  [string] $BatchId = '',
  [switch] $DeployBastion
)

$ErrorActionPreference = 'Stop'
foreach ($m in 'Az.Accounts', 'Az.Network') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}

$resolvedPeerVnetId = $PeerVnetId
$testVmRg = ''
$testVmResourceName = ''
if (-not $resolvedPeerVnetId) {
  $vnet = $null
  if ($TestVmName) {
    $testVmRg = "rg-$TestVmName-$Environment-vm"
    $testVmResourceName = "vm-$TestVmName"
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $testVmRg -Name "vnet-$TestVmName-vm" -ErrorAction SilentlyContinue
  }
  else {
    $vnet = @(Get-AzVirtualNetwork | Where-Object { $_.ResourceGroupName -like "rg-*-$Environment-vm" -and $_.Name -like 'vnet-*-vm' }) | Select-Object -First 1
    if ($vnet) {
      $testVmRg = $vnet.ResourceGroupName
      $inferredName = ($vnet.Name -replace '^vnet-', '' -replace '-vm$', '')
      $testVmResourceName = "vm-$inferredName"
    }
  }
  if ($vnet) {
    $resolvedPeerVnetId = $vnet.Id
    if (-not $PSBoundParameters.ContainsKey('Location') -and $vnet.Location) {
      $Location = $vnet.Location
    }
    Write-Host "Discovered test VM VNet: $($vnet.Name) in $testVmRg ($($vnet.Location), $($vnet.AddressSpace.AddressPrefixes -join ', '))"
  }
}

$deployParams = @{
  Action               = $Action
  NamePrefix           = $Name
  Environment          = $Environment
  Location             = $Location
  HubPlan              = $HubPlan
  HubVmSize            = $HubVmSize
  ShutdownAfterMinutes = $ShutdownAfterMinutes
  TeardownAfterMinutes = $TeardownAfterMinutes
  NoBastion            = (-not $DeployBastion.IsPresent)
}
if ($resolvedPeerVnetId) { $deployParams.PeerVnetId = $resolvedPeerVnetId }
if ($BatchId) { $deployParams.BatchId = $BatchId }
if ($WhatIfPreference) { $deployParams.WhatIf = $true }

& (Join-Path $PSScriptRoot 'Deploy-Stratusphere.ps1') @deployParams
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0 -and $Action -in 'Plan', 'Deploy') {
  Write-Host ''
  Write-Host 'Next commands:'
  if ($testVmRg -and $testVmResourceName) {
    Write-Host "  Roll out Connector ID Key to ${testVmResourceName}:"
    Write-Host "    ./scripts/ops/Deploy-CidKey.ps1 -ResourceGroupName $testVmRg -VmName $testVmResourceName -Action Check"
    Write-Host "    ./scripts/ops/Deploy-CidKey.ps1 -ResourceGroupName $testVmRg -VmName $testVmResourceName -Action Install -HubAddress 10.60.0.4 -InstallerUrl <https-url> -InstallerSha256 <sha256>"
  }
  Write-Host '  Deallocate Hub only (stop compute meter, keep disk and peering):'
  Write-Host "    ./scripts/ops/Remove-SandboxStratusphere.ps1 -Name $Name -Environment $Environment -DeallocateOnly"
  Write-Host '  Full teardown (removes remote VNet peering first, deletes RG, and disarms aa-avdlz-runs schedules):'
  Write-Host "    ./scripts/ops/Remove-SandboxStratusphere.ps1 -Name $Name -Environment $Environment -Force -DiscardLastCopy"
}
exit $exitCode
