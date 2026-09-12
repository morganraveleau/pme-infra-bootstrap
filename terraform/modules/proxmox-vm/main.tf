# Module réutilisable : clone un template cloud-init et configure la VM
# (CPU / RAM / disque / IP / SSH). Utilisé pour k3s-node1 et ad-dc1.

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

  # Console série héritée du template cloud Debian
  serial_device {}
  vga { type = "serial0" }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
    # Injection de la clé SSH publique via cloud-init → Ansible peut se connecter
    user_account {
      username = "debian"
      keys     = [var.ssh_public_key]
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # Évite de recréer la VM si l'IP est modifiée à la main pendant les tests
      initialization,
    ]
  }
}
