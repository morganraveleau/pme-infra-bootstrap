terraform {
  required_version = ">= 1.7.0"

  required_providers {
    # bpg/proxmox : provider communautaire le plus actif pour Proxmox VE en 2026.
    # (l'alternative historique telmate/proxmox fonctionne aussi mais est moins maintenue)
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
  }
}
