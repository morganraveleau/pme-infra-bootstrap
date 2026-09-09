variable "name" {
  description = "Nom de la VM dans Proxmox"
  type        = string
}

variable "node_name" {
  description = "Noeud Proxmox cible"
  type        = string
}

variable "template_id" {
  description = "ID du template (VM Proxmox) cloud-init à cloner"
  type        = number
}

variable "vcpu" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  type    = number
  default = 20
}

variable "ip_address" {
  description = "Adresse IP au format CIDR, ex: 192.168.1.50/24"
  type        = string
}

variable "gateway" {
  type = string
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "tags" {
  type    = list(string)
  default = []
}
