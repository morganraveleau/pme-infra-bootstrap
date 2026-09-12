# =============================================================================
# variables.pkr.hcl — Variables Packer pour Windows Server 2022 sur Proxmox
# Les variables Proxmox sont identiques à celles de Terraform.
# =============================================================================

variable "pm_api_url" {
  type        = string
  description = "URL de l'API Proxmox (ex : https://192.168.1.10:8006/api2/json)"
}

variable "pm_api_token_id" {
  type        = string
  description = "ID du token API (ex : terraform@pve!terraform-token)"
}

variable "pm_api_token_secret" {
  type        = string
  description = "Secret du token API Proxmox"
  sensitive   = true
}

variable "pm_node" {
  type        = string
  description = "Nom du nœud Proxmox (ex : pve)"
}

variable "network_bridge" {
  type        = string
  description = "Bridge réseau Proxmox"
  default     = "vmbr0"
}

variable "datastore" {
  type        = string
  description = "Stockage cible pour le disque du template (ex : local-lvm)"
}

variable "windows_iso_file" {
  type        = string
  description = <<-EOT
    Nom du fichier ISO Windows Server 2022 déjà uploadé dans le stockage 'local'
    de Proxmox (ex : Windows_Server_2022_x64_FR_Eval.iso).
    Télécharger depuis : https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
  EOT
}

variable "windows_admin_password" {
  type        = string
  description = "Mot de passe Administrateur temporaire utilisé par Packer pour se connecter via WinRM. Cloudbase-init le réinitialisera au 1er boot de la VM."
  sensitive   = true
  default     = "Packer2024!"
}
