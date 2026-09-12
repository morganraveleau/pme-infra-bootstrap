terraform {
  required_version = ">= 1.7.0"

  required_providers {
    # bpg/proxmox : provider communautaire le plus actif pour Proxmox VE.
    # SSH requis sur le noeud Proxmox pour l'import des disques cloud-init.
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}
