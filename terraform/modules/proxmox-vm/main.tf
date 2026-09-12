# Module réutilisable : clone un template cloud-init/cloudbase-init et configure la VM.
# Utilisé pour k3s-node1 (Linux) et ad-dc1 (Windows).

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name

  clone {
    vm_id = var.template_id
    full  = true
  }

  # qemu-guest-agent nécessaire pour que Proxmox récupère l'IP réelle de la VM
  agent {
    enabled = true
  }

  cpu {
    cores = var.vcpu
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = var.disk_gb
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  # Console série héritée des templates cloud
  serial_device {}
  vga { type = "serial0" }

  # Configuration réseau via cloud-init (Linux) ou cloudbase-init (Windows)
  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    # user_account : uniquement pour Linux (cloud-init injecte la clé SSH)
    # Pour Windows, cloudbase-init gère son propre user-data depuis le template.
    dynamic "user_account" {
      for_each = var.is_windows ? [] : [1]
      content {
        username = "debian"
        keys     = [var.ssh_public_key]
      }
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}
