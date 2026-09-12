# Toutes ces valeurs sont normalement écrites automatiquement dans
# terraform.tfvars.json par le formulaire web (webapp-config/).
# Voir terraform.tfvars.example pour remplir à la main pendant le dev.

# --- Connexion Proxmox API ---

variable "pm_api_url" {
  description = "URL de l'API Proxmox, ex: https://192.168.1.10:8006/api2/json"
  type        = string
}

variable "pm_api_token_id" {
  description = "ID du token API Proxmox, ex: terraform@pve!terraform-token"
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

variable "pm_node_address" {
  description = "Adresse IP du noeud Proxmox — utilisée par le provider bpg/proxmox pour la connexion SSH (import disques cloud-init)"
  type        = string
  default     = "192.168.1.10"
}

variable "pm_ssh_private_key_path" {
  description = "Chemin vers la clé privée SSH root du noeud Proxmox (pour le provider bpg/proxmox)"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# --- Paramètres généraux ---

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

variable "datastore" {
  description = "Stockage Proxmox pour les disques VM (doit supporter le content-type 'images')"
  type        = string
  default     = "local-lvm"
}

variable "ssh_public_key" {
  description = "Clé publique SSH injectée via cloud-init dans les VMs Linux (permet la connexion Ansible)"
  type        = string
}

# --- VM k3s ---

variable "k3s_vm" {
  description = "Dimensionnement de la VM k3s (control-plane + worker unique en V1)"
  type = object({
    vcpu      = optional(number, 2)
    memory_mb = optional(number, 4096)
    disk_gb   = optional(number, 40)
    ip_address = string # CIDR, ex: 192.168.1.50/24
    gateway    = string
  })
}

# --- VM Active Directory ---

variable "ad_vm" {
  description = "Dimensionnement de la VM contrôleur de domaine Active Directory"
  type = object({
    template_id = number  # ID du template Windows Server dans Proxmox (créé manuellement — voir docs/architecture.md)
    vcpu        = optional(number, 2)
    memory_mb   = optional(number, 4096)
    disk_gb     = optional(number, 80)
    ip_address  = string
    gateway     = string
  })
}
