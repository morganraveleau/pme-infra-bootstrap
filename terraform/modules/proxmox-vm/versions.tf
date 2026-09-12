# Un module qui utilise un provider avec un "source" non-officiel (bpg/proxmox)
# doit déclarer lui-même ce required_providers, sinon Terraform suppose par
# défaut le namespace hashicorp/* pour ce module et échoue à trouver le provider.
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}
