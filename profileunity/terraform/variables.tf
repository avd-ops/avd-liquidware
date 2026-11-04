# Parameters for the ProfileUnity and FlexApp tier (docs/deploy-spec.md sections 4 and 5).
# Variable names match profileunity/bicep/main.bicep so Get-LwTemplateParameter feeds both engines.
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

variable "location" {
  description = "Region of the landing zone (Deploy-LiquidwareTier.ps1 passes the spoke VNet location)."
  type        = string
}

variable "namePrefix" {
  description = "The landing zone prefix (2-8 lowercase letters, digits or hyphens)."
  type        = string

  validation {
    condition     = length(var.namePrefix) >= 2 && length(var.namePrefix) <= 8 && can(regex("^[a-z0-9-]+$", var.namePrefix))
    error_message = "namePrefix must be 2-8 lowercase letters, digits or hyphens."
  }
}

variable "environment" {
  description = "Landing zone environment (dev, test or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "tierAddressPrefix" {
  description = "The tier VNet. /24 or larger; must not overlap the spoke, its peers or the Stratusphere VNet."
  type        = string
  default     = "10.61.0.0/24"
}

variable "spokeVnetId" {
  description = "Resource ID of the landing zone spoke VNet (vnet-<base>)."
  type        = string
}

variable "spokeAddressPrefixes" {
  description = "The spoke address space. The tier NSGs deny outbound to it."
  type        = list(string)
}

variable "sessionHostSubnetPrefix" {
  description = "Prefix of snet-session-hosts: the only source allowed to reach the console (443, licensing)."
  type        = string
}

variable "spokePrivateEndpointSubnetPrefix" {
  description = "Prefix of the spoke private endpoint subnet: the one part of the spoke the tier may reach (the profiles account)."
  type        = string
}

variable "fileDnsZoneId" {
  description = "Resource ID of the landing zone privatelink.file zone (Standalone mode)."
  type        = string
}

variable "vaultDnsZoneId" {
  description = "Resource ID of the landing zone privatelink.vaultcore zone (Standalone mode)."
  type        = string
}

variable "usersGroupObjectId" {
  description = "Object ID of the landing zone users group (the group with SMB Share Contributor on the profiles account)."
  type        = string
}

variable "avdServicePrincipalObjectIds" {
  description = "Object IDs of the Azure Virtual Desktop and Azure Virtual Desktop ARM Provider service principals in this tenant."
  type        = list(string)
}

variable "deployBastion" {
  description = "Add AzureBastionSubnet and allow 3389 from it to the console and packaging subnets."
  type        = bool
  default     = false
}

variable "operatorObjectId" {
  description = "Object ID of the operator running the deploy: uploads installers to media and may read the console password."
  type        = string
}

variable "consoleExists" {
  description = "True when the console VM already exists: the deploy then leaves the VM and its password alone (lesson 0002)."
  type        = bool
  default     = false
}

variable "consolePrincipalId" {
  description = "The existing console VM identity, when consoleExists."
  type        = string
  default     = ""
}

variable "consoleAdminPassword" {
  description = "Generated in memory by Deploy-LiquidwareTier.ps1 for a new console only; written to the tier Key Vault, never output."
  type        = string
  sensitive   = true
  default     = ""
}

variable "licenseStored" {
  description = "True once Set-LiquidwareSecret.ps1 has stored lw-licstr in the tier Key Vault."
  type        = bool
  default     = false
}

variable "autoShutdownTime" {
  description = "Daily console shutdown in dev and test, HHmm."
  type        = string
  default     = "1900"
}

variable "enablePortability" {
  description = "Create the portability share on the existing landing zone profiles storage account."
  type        = bool
  default     = false
}

variable "profilesStorageAccountName" {
  description = "Name of the existing landing zone profiles storage account (when enablePortability is true)."
  type        = string
  default     = ""
}

variable "profilesResourceGroupName" {
  description = "Resource group of the existing landing zone profiles storage account (when enablePortability is true)."
  type        = string
  default     = ""
}

variable "enableApplicationRestrictions" {
  description = "Create the tier data collection rule for ProfileUnity application restriction events."
  type        = bool
  default     = false
}

variable "logAnalyticsWorkspaceId" {
  description = "Resource ID of the landing zone Log Analytics workspace (when enableApplicationRestrictions is true)."
  type        = string
  default     = ""
}

variable "deployPackagingVm" {
  description = "Deploy the on-demand FlexApp packaging VM in snet-lw-packaging."
  type        = bool
  default     = false
}

variable "packagingAdminPassword" {
  description = "Generated in memory by Deploy-LiquidwareTier.ps1 for the packaging VM only; written to the tier Key Vault."
  type        = string
  sensitive   = true
  default     = ""
}

variable "enableBackup" {
  description = "Create the tier Recovery Services vault with an Enhanced backup policy."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto the tier resource group and resources."
  type        = map(string)
  default     = {}
}
