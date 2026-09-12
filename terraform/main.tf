provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = true # passer à false une fois un certificat TLS valide en place

  # SSH requis par le provider bpg/proxmox pour importer les disques cloud-init
  # et certaines opérations de bas niveau sur le noeud.
  ssh {
    username    = "root"
    private_key = file(pathexpand(var.pm_ssh_private_key_path))
    node {
      name    = var.pm_node
      address = var.pm_node_address
    }
  }
}

# ---------------------------------------------------------------------------
# ÉTAPE 1 — Télécharger l'image cloud Debian 12 sur le stockage Proxmox
# Le provider déclenche un job de téléchargement via l'API Proxmox ;
# Proxmox va lui-même chercher l'image sur internet.
# ---------------------------------------------------------------------------
resource "proxmox_download_file" "debian12_cloud_image" {
  content_type        = "iso"
  datastore_id        = "local" # le stockage "local" (type dir) supporte le content-type iso
  node_name           = var.pm_node
  url                 = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name           = "debian-12-genericcloud-amd64.img"
  overwrite_unmanaged = true

  # Décommenter pour vérifier l'intégrité (recommandé en prod) :
  # checksum_algorithm = "sha512"
  # checksum           = "<sha512-from-debian-website>"
}

# ---------------------------------------------------------------------------
# ÉTAPE 2 — Créer le template Debian 12 cloud-init (VM id 9000)
# Ce template sera cloné pour chaque VM Linux du projet.
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "debian12_template" {
  name      = "debian12-cloud-init-tpl"
  node_name = var.pm_node
  vm_id     = 9000
  template  = true   # marque la VM comme template — ne démarre pas

  agent {
    enabled = true  # qemu-guest-agent installé via cloud-init au 1er boot
  }

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = 512
  }

  # Disque principal importé depuis l'image cloud téléchargée ci-dessus.
  # bpg/proxmox utilise SSH pour importer le disque via qm importdisk.
  disk {
    datastore_id = var.datastore
    file_id      = proxmox_download_file.debian12_cloud_image.id
    interface    = "scsi0"
    discard      = "on"
    size         = 8  # taille minimale ; le clone sera redimensionné à var.k3s_vm.disk_gb
  }

  # Disque cloud-init (seed drive — contient user-data/network-config)
  disk {
    datastore_id = var.datastore
    interface    = "ide2"
    file_format  = "raw"
    size         = 4
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # Console série (nécessaire pour les images cloud Debian — pas de VGA par défaut)
  serial_device {}
  vga { type = "serial0" }

  initialization {
    ip_config {
      ipv4 { address = "dhcp" }
    }
    user_account {
      username = "debian"
      keys     = [var.ssh_public_key]
    }
  }
}

# ---------------------------------------------------------------------------
# VM 1 — k3s-node1 : control-plane + worker (clone du template Debian 12)
# ---------------------------------------------------------------------------
module "k3s_node1" {
  source = "./modules/proxmox-vm"

  name           = "${var.company_name}-k3s-node1"
  node_name      = var.pm_node
  template_id    = proxmox_virtual_environment_vm.debian12_template.vm_id
  vcpu           = var.k3s_vm.vcpu
  memory_mb      = var.k3s_vm.memory_mb
  disk_gb        = var.k3s_vm.disk_gb
  ip_address     = var.k3s_vm.ip_address
  gateway        = var.k3s_vm.gateway
  bridge         = var.network_bridge
  datastore      = var.datastore
  ssh_public_key = var.ssh_public_key
  tags           = ["bootstrap-pme", "k3s"]

  depends_on = [proxmox_virtual_environment_vm.debian12_template]
}

# ---------------------------------------------------------------------------
# VM 2 — ad-dc1 : contrôleur de domaine Active Directory (Windows Server)
# PRÉREQUIS : un template Windows Server (cloudbase-init inclus) doit exister
# dans Proxmox avec l'ID défini dans var.ad_vm.template_id (défaut : 9001).
# Voir docs/architecture.md#windows-template pour la procédure de création.
# ---------------------------------------------------------------------------
module "ad_dc1" {
  source = "./modules/proxmox-vm"

  name           = "${var.company_name}-ad-dc1"
  node_name      = var.pm_node
  template_id    = var.ad_vm.template_id
  vcpu           = var.ad_vm.vcpu
  memory_mb      = var.ad_vm.memory_mb
  disk_gb        = var.ad_vm.disk_gb
  ip_address     = var.ad_vm.ip_address
  gateway        = var.ad_vm.gateway
  bridge         = var.network_bridge
  datastore      = var.datastore
  ssh_public_key = var.ssh_public_key
  tags           = ["bootstrap-pme", "active-directory"]
}
