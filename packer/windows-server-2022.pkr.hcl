# =============================================================================
# windows-server-2022.pkr.hcl
# Crée le template Proxmox Windows Server 2022 (vm_id 9001) :
#   1. Installe Windows depuis ISO (disque SATA pour éviter les drivers en phase setup)
#   2. Packer se connecte via WinRM (configuré par autounattend.xml)
#   3. Scripts PowerShell : VirtIO drivers → cloudbase-init → WinRM Ansible
#   4. Sysprep + shutdown → Proxmox convertit en template
# =============================================================================

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "windows-server-2022" {

  # ---------------------------------------------------------------------------
  # Connexion Proxmox (identique au provider Terraform bpg/proxmox)
  # ---------------------------------------------------------------------------
  proxmox_url              = var.pm_api_url
  username                 = "${var.pm_api_token_id}!${var.pm_api_token_secret}"
  insecure_skip_tls_verify = true
  node                     = var.pm_node

  # ---------------------------------------------------------------------------
  # VM template
  # ---------------------------------------------------------------------------
  vm_id   = 9001
  vm_name = "windows-server-2022-tpl"

  template_name        = "windows-server-2022-tpl"
  template_description = "Windows Server 2022 Standard — cloudbase-init — créé par Packer Bootstrap PME"

  os           = "win11"   # Type Proxmox le plus proche pour Windows Server 2022
  qemu_agent   = true      # Le script d'install activera le service QEMU guest agent

  # ---------------------------------------------------------------------------
  # ISO Windows Server 2022 (déjà uploadé dans le stockage local Proxmox)
  # ---------------------------------------------------------------------------
  boot_iso {
    iso_file         = "local:iso/${var.windows_iso_file}"
    unmount          = true
  }

  # ---------------------------------------------------------------------------
  # ISOs additionnels
  # ---------------------------------------------------------------------------

  # VirtIO drivers — téléchargés automatiquement par Proxmox depuis Fedora
  additional_iso_files {
    iso_url          = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    iso_checksum     = "none"    # Dernière version stable, hash variable — à fixer en prod
    iso_storage_pool = "local"
    device           = "ide1"
    unmount          = true
  }

  # Disque CD contenant autounattend.xml (répond automatiquement à l'installeur Windows)
  additional_iso_files {
    cd_files = ["./http/autounattend.xml"]
    cd_label = "AUTOUNATTEND"
    device   = "ide2"
    unmount  = false
  }

  # ---------------------------------------------------------------------------
  # Matériel de la VM de build
  # Disque SATA : Windows Setup n'a pas besoin du driver VirtIO pendant l'install.
  # NIC E1000  : idem, driver intégré à Windows — VirtIO sera installé par script.
  # ---------------------------------------------------------------------------
  cores   = 4
  memory  = 4096
  cpu_type = "host"

  disks {
    type             = "sata"
    disk_size        = "80G"
    storage_pool     = var.datastore
    format           = "raw"
  }

  network_adapters {
    model  = "e1000"
    bridge = var.network_bridge
  }

  # Serial console (requis par cloudbase-init pour les logs)
  serials = ["socket"]

  # ---------------------------------------------------------------------------
  # Boot : laisser le temps au BIOS de démarrer, puis appuyer sur une touche
  # pour lancer le boot depuis l'ISO. autounattend.xml prend ensuite le relais.
  # ---------------------------------------------------------------------------
  boot_wait    = "5s"
  boot_command = ["<spacebar>"]

  # ---------------------------------------------------------------------------
  # Communicateur WinRM
  # Configuré par autounattend.xml (FirstLogonCommands).
  # Packer réessaie pendant winrm_timeout (l'install Windows prend ~15-30 min).
  # ---------------------------------------------------------------------------
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.windows_admin_password
  winrm_use_ssl  = false    # HTTP suffisant pour le réseau local de build
  winrm_insecure = true
  winrm_timeout  = "2h"
}

# =============================================================================
# Build
# =============================================================================
build {
  sources = ["source.proxmox-iso.windows-server-2022"]

  # 1. Installer les drivers VirtIO depuis l'ISO monté en ide1
  provisioner "powershell" {
    script = "./scripts/01-install-virtio.ps1"
  }

  # 2. Redémarrer pour activer les nouveaux drivers
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # 3. Installer cloudbase-init (gestion cloud-init Proxmox au 1er boot)
  provisioner "powershell" {
    script = "./scripts/02-install-cloudbase-init.ps1"
  }

  # 4. Configurer WinRM pour Ansible + nettoyage final + sysprep
  #    Le sysprep arrête la VM → Packer détecte le shutdown et crée le template.
  provisioner "powershell" {
    script = "./scripts/03-finalize.ps1"
  }
}
