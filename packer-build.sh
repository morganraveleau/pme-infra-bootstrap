#!/usr/bin/env bash
# =============================================================================
# packer-build.sh — Créer le template Windows Server 2022 (vm_id 9001) sur Proxmox
#
# Entièrement automatisé :
#   1. Terraform déclenche le téléchargement de l'ISO Windows sur Proxmox (~5.4 Go)
#   2. Packer installe Windows, configure VirtIO + cloudbase-init, sysprep → template
#
# Prérequis :
#   - terraform installé (https://developer.hashicorp.com/terraform)
#   - packer installé   (https://developer.hashicorp.com/packer/downloads)
#   - terraform/terraform.tfvars rempli (connexion Proxmox)
#   - packer/windows-server-2022.pkrvars.hcl rempli (copier depuis .example)
#
# Usage : ./packer-build.sh
# Durée : 10-20 min (téléchargement ISO) + 30-45 min (installation Windows)
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
PACKER_DIR="$ROOT_DIR/packer"
PKRVARS="$PACKER_DIR/windows-server-2022.pkrvars.hcl"

# WSL / NTFS : providers Terraform sur le FS Linux natif
export TF_DATA_DIR="${HOME}/.terraform-data/pme-infra-bootstrap"
mkdir -p "$TF_DATA_DIR"

log()  { printf '\n\033[1;33m==> %s\033[0m\n' "$1"; }
err()  { printf '\033[1;31mErreur : %s\033[0m\n' "$1" >&2; exit 1; }
info() { printf '    %s\n' "$1"; }

# =============================================================================
# 1. Pré-requis
# =============================================================================
log "Vérification des pré-requis"

command -v terraform >/dev/null 2>&1 || err "terraform non trouvé — https://developer.hashicorp.com/terraform"
command -v packer    >/dev/null 2>&1 || err "packer non trouvé — https://developer.hashicorp.com/packer/downloads"

info "terraform : $(terraform version -json | python3 -c 'import sys,json;print(json.load(sys.stdin)["terraform_version"])')"
info "packer    : $(packer version)"

[[ -f "$PKRVARS" ]] || err "Fichier de variables Packer introuvable : $PKRVARS
Copie et remplis le fichier exemple :
  cp packer/windows-server-2022.pkrvars.hcl.example packer/windows-server-2022.pkrvars.hcl"

# =============================================================================
# 2. Téléchargement de l'ISO Windows Server 2022 sur Proxmox via Terraform
#    Proxmox va chercher l'ISO directement sur les serveurs Microsoft (~5.4 Go).
#    Si le fichier existe déjà dans Proxmox, cette étape est instantanée.
# =============================================================================
log "Terraform init"
terraform -chdir="$TF_DIR" init -input=false

log "Téléchargement ISO Windows Server 2022 → Proxmox (première fois : 10-20 min)"
info "Proxmox télécharge l'ISO directement depuis Microsoft — progression dans l'interface Proxmox."
info "(Tasks → datacenter → storage → local → ISO Images)"

terraform -chdir="$TF_DIR" apply \
  -target=proxmox_download_file.windows_server_2022_iso \
  -input=false \
  -auto-approve

# Récupérer le nom du fichier ISO depuis l'output Terraform
WIN_ISO=$(terraform -chdir="$TF_DIR" output -raw windows_server_2022_iso_filename)
info "ISO disponible dans Proxmox : local:iso/${WIN_ISO}"

# =============================================================================
# 3. Packer init (télécharge le plugin proxmox si absent)
# =============================================================================
log "Packer init (plugin Proxmox)"
packer init "$PACKER_DIR/windows-server-2022.pkr.hcl"

# =============================================================================
# 4. Validation Packer
# =============================================================================
log "Packer validate"
packer validate \
  -var "windows_iso_file=${WIN_ISO}" \
  -var-file="$PKRVARS" \
  "$PACKER_DIR/windows-server-2022.pkr.hcl"

# =============================================================================
# 5. Build Packer
#    - Crée une VM temporaire dans Proxmox
#    - Installe Windows depuis l'ISO
#    - Se connecte via WinRM (configuré par autounattend.xml)
#    - Installe VirtIO drivers, cloudbase-init, configure WinRM pour Ansible
#    - Lance le sysprep → Proxmox convertit la VM en template (vm_id 9001)
# =============================================================================
log "Packer build — template Windows Server 2022 (vm_id 9001)"
info "Durée estimée : 30-45 minutes."
info "La VM temporaire est visible dans l'interface Proxmox pendant le build."

packer build \
  -var "windows_iso_file=${WIN_ISO}" \
  -var-file="$PKRVARS" \
  "$PACKER_DIR/windows-server-2022.pkr.hcl"

# =============================================================================
log "Template Windows Server 2022 créé ! (vm_id 9001)"
printf '\n'
printf '  Le template est disponible dans Proxmox.\n'
printf '  Lance maintenant ./deploy.sh pour provisionner toutes les VMs.\n'
printf '\n'
