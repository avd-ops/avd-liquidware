# =====================================================================
# AVD readiness with Stratusphere UX -- assessment environment variables
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
# =====================================================================

# ---------- Core ----------

variable "namePrefix" {
  description = "Short prefix (lowercase letters/digits, 2-8 chars). Resource names derive from this."
  type        = string
  default     = "ssux"

  validation {
    condition     = length(var.namePrefix) >= 2 && length(var.namePrefix) <= 8 && can(regex("^[a-z0-9]+$", var.namePrefix))
    error_message = "namePrefix must be 2-8 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Optional environment segment (dev, test, prod) so the resource group matches rg-<prefix>-<env>-* for deadline teardown."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "dev", "test", "prod"], var.environment)
    error_message = "environment must be empty or one of: dev, test, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Extra tags merged onto the resource group and every resource."
  type        = map(string)
  default     = {}
}

# ---------- Appliance images (Azure Marketplace) ----------

variable "imagePublisher" {
  description = "Marketplace publisher of the Stratusphere images."
  type        = string
  default     = "liquidware"
}

variable "imageOffer" {
  description = "Marketplace offer of the Stratusphere images."
  type        = string
  default     = "stratusphere"
}

variable "imageVersion" {
  description = "Image version for every appliance, or latest."
  type        = string
  default     = "latest"
}

# ---------- Hub ----------

variable "deployHub" {
  description = "Deploy the Hub. Turned off only to change other roles without touching it."
  type        = bool
  default     = true
}

variable "hubImagePlan" {
  description = "Marketplace plan (SKU) of the Hub. The preflight lists the plans offered in your region."
  type        = string

  validation {
    condition     = length(var.hubImagePlan) >= 1
    error_message = "hubImagePlan must not be empty."
  }
}

variable "hubVmSize" {
  description = "Hub VM size. Liquidware lists 4 vCPU and 16 GB as the Hub minimum."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "hubOsDiskSizeGB" {
  description = "OS disk size in GB for the Hub. Liquidware lists 60 GB as the minimum; the database grows with endpoints and retention."
  type        = number
  default     = 128

  validation {
    condition     = var.hubOsDiskSizeGB >= 64
    error_message = "hubOsDiskSizeGB must be at least 64."
  }
}

variable "hubPrivateIp" {
  description = "Static private IP of the Hub, inside hubSubnetPrefix (Azure reserves the first four addresses)."
  type        = string
  default     = "10.60.0.4"
}

# ---------- Database (optional) ----------

variable "deployDatabase" {
  description = "Deploy the Database appliance. Liquidware advises one above 1,000 Connector ID Keys."
  type        = bool
  default     = false
}

variable "databaseImagePlan" {
  description = "Marketplace plan (SKU) of the Database appliance. Required when deployDatabase is true."
  type        = string
  default     = ""
}

variable "databaseVmSize" {
  description = "Database VM size. Liquidware lists 4 vCPU and 16 GB as the minimum."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "databaseOsDiskSizeGB" {
  description = "OS disk size in GB for the Database appliance."
  type        = number
  default     = 256

  validation {
    condition     = var.databaseOsDiskSizeGB >= 64
    error_message = "databaseOsDiskSizeGB must be at least 64."
  }
}

variable "databasePrivateIp" {
  description = "Static private IP of the Database appliance."
  type        = string
  default     = "10.60.0.5"
}

# ---------- Collectors (optional) ----------

variable "collectorCount" {
  description = "Number of Collector appliances (0 for none)."
  type        = number
  default     = 0

  validation {
    condition     = var.collectorCount >= 0 && var.collectorCount <= 4
    error_message = "collectorCount must be between 0 and 4."
  }
}

variable "collectorImagePlan" {
  description = "Marketplace plan (SKU) of the Collector appliance. Required when collectorCount is above 0."
  type        = string
  default     = ""
}

variable "collectorVmSize" {
  description = "Collector VM size. Liquidware lists 2 vCPU and 8 GB as the minimum."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "collectorOsDiskSizeGB" {
  description = "OS disk size in GB for each Collector."
  type        = number
  default     = 64

  validation {
    condition     = var.collectorOsDiskSizeGB >= 32
    error_message = "collectorOsDiskSizeGB must be at least 32."
  }
}

variable "collectorPrivateIps" {
  description = "Static private IPs of the Collectors, in order. Needs at least collectorCount entries."
  type        = list(string)
  default = [
    "10.60.0.10",
    "10.60.0.11",
    "10.60.0.12",
    "10.60.0.13",
  ]
}

variable "autoShutdownTime" {
  description = "Daily auto-shutdown time in HHmm (24-hour) for every appliance VM, or empty to disable."
  type        = string
  default     = "2000"
}

variable "autoShutdownTimeZone" {
  description = "Windows time zone ID for the daily auto-shutdown schedule."
  type        = string
  default     = "Central Standard Time"
}

# ---------- Appliance credential ----------

variable "adminUsername" {
  description = "Local administrator name Azure sets on every appliance."
  type        = string
  default     = "ssadmin-azure"
}

variable "adminPassword" {
  description = "Local administrator password Azure sets on every appliance. The deploy scripts generate one, store it in Key Vault and reuse it on later runs."
  type        = string
  sensitive   = true
}

# ---------- Network ----------

variable "addressPrefix" {
  description = "Address space of the assessment VNet."
  type        = string
  default     = "10.60.0.0/24"
}

variable "hubSubnetPrefix" {
  description = "Subnet for the appliances: Hub, Database and Collectors."
  type        = string
  default     = "10.60.0.0/26"
}

variable "bastionSubnetPrefix" {
  description = "AzureBastionSubnet prefix (/26 or larger). Used only when deployBastion is true."
  type        = string
  default     = "10.60.0.64/26"
}

variable "callbackSourcePrefixes" {
  description = "Source prefixes allowed to reach the Hub on TCP 443: the endpoints running the Connector ID Key and the admins using the web console."
  type        = list(string)
  default = [
    "VirtualNetwork",
  ]
}

variable "peerVirtualNetworkResourceId" {
  description = "Optional VNet to peer with both ways (for example the avd-landing-zone spoke whose session hosts will run the Connector ID Key). Empty for none."
  type        = string
  default     = ""
}

variable "deployBastion" {
  description = "Deploy Azure Bastion (Basic) for the appliance console."
  type        = bool
  default     = true
}

# ---------- Access ----------

variable "keyVaultReaderObjectId" {
  description = "Object ID of the user or group allowed to read the appliance credential from Key Vault (the deploy scripts pass the signed-in user)."
  type        = string
}

variable "keyVaultReaderPrincipalType" {
  description = "Principal type of keyVaultReaderObjectId."
  type        = string
  default     = "User"

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.keyVaultReaderPrincipalType)
    error_message = "keyVaultReaderPrincipalType must be one of: User, Group, ServicePrincipal."
  }
}
