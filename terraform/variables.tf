# Toutes ces valeurs sont normalement écrites automatiquement dans
# terraform.tfvars.json par le formulaire web (webapp-config/).
# Voir terraform.tfvars.example pour remplir à la main pendant le dev.

variable "pm_api_url" {
  description = "URL de l'API Proxmox, ex: https://192.168.1.10:8006/api2/json"
  type        = string
}

variable "pm_api_token_id" {
  description = "ID du token API Proxmox, ex: terraform@pve!bootstrap"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Secret du token API Proxmox"
  type        = string
  sensitive   = true
}

variable "pm_node" {
  description = "Nom du noeud Proxmox cible (ex: pve)"
  type        = string
}

variable "company_name" {
  description = "Nom de la PME, utilisé comme préfixe pour nommer les VMs"
  type        = string
  default     = "acme"
}

variable "network_bridge" {
  description = "Bridge réseau Proxmox à utiliser (ex: vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "k3s_vm" {
  description = "Dimensionnement de la VM k3s (control-plane + worker unique en V1)"
  type = object({
    template_id = number
    vcpu        = optional(number, 2)
    memory_mb   = optional(number, 4096)
    disk_gb     = optional(number, 40)
    ip_address  = string # CIDR, ex: 192.168.1.50/24
    gateway     = string
  })
}

variable "ad_vm" {
  description = "Dimensionnement de la VM contrôleur de domaine Active Directory"
  type = object({
    template_id = number
    vcpu        = optional(number, 2)
    memory_mb   = optional(number, 4096)
    disk_gb     = optional(number, 80)
    ip_address  = string
    gateway     = string
  })
}
