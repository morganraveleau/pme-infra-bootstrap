# Module réutilisable : clone un template cloud-init existant et l'ajuste
# (CPU/RAM/disque/IP). Utilisé à la fois pour k3s-node1 et ad-dc1 (J3-J4 de la roadmap).
#
# NB : pour la VM Windows (ad-dc1), le template doit déjà avoir cloudbase-init
# (équivalent Windows de cloud-init) configuré, ou bien un provisioning
# complémentaire via winrm sera nécessaire côté Ansible (rôle ad_domain_controller).

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name

  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = var.vcpu
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.disk_gb
  }

  network_device {
    bridge = var.bridge
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # évite de recréer la VM si quelqu'un modifie l'IP à la main pendant les tests
      initialization,
    ]
  }
}
