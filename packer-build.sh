#!/usr/bin/env bash
# =============================================================================
# packer-build.sh — Créer le template Windows Server 2022 (vm_id 9001) sur Proxmox
#
# Prérequis :
#   1. Packer installé : https://developer.hashicorp.com/packer/downloads
#   2. ISO Windows Server 2022 uploadé dans le stockage local Proxmox
#      Télécharger : https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
#   3. Fichier packer/windows-server-2022.pkrvars.hcl rempli (copier depuis .example)
#
# Usage : ./packer-build.sh
# Durée : ~30-45 minutes (installation Windows complète)
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$ROOT_DIR/packer"
PKRVARS="$PACKER_DIR/windows-server-2022.pkrvars.hcl"

log()  { printf '\n\033[1;33m==> %s\033[0m\n' "$1"; }
err()  { printf '\033[1;31mErreur : %s\033[0m\n' "$1" >&2; exit 1; }
info() { printf '    %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Pré-requis
# ---------------------------------------------------------------------------
log "Vérification des pré-requis"

command -v packer >/dev/null 2>&1 || err "packer non trouvé — installe-le depuis https://developer.hashicorp.com/packer/downloads"
info "packer : $(packer version)"

[[ -f "$PKRVARS" ]] || err "Fichier de variables introuvable : $PKRVARS
Copie et remplis le fichier exemple :
  cp packer/windows-server-2022.pkrvars.hcl.example packer/windows-server-2022.pkrvars.hcl"

# ---------------------------------------------------------------------------
# Initialisation (télécharge le plugin proxmox pour Packer)
# ---------------------------------------------------------------------------
log "Packer init (plugin Proxmox)"
packer init "$PACKER_DIR/windows-server-2022.pkr.hcl"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
log "Packer validate"
packer validate \
    -var-file="$PKRVARS" \
    "$PACKER_DIR/windows-server-2022.pkr.hcl"

# ---------------------------------------------------------------------------
# Build — installe Windows, configure VirtIO + cloudbase-init, sysprep
# ---------------------------------------------------------------------------
log "Packer build (template Windows Server 2022 → vm_id 9001)"
info "Durée estimée : 30-45 minutes selon les performances du stockage Proxmox."
info "Suivi en direct dans la console Proxmox : VM temporaire visible pendant le build."

packer build \
    -var-file="$PKRVARS" \
    "$PACKER_DIR/windows-server-2022.pkr.hcl"

# ---------------------------------------------------------------------------
log "Template Windows Server 2022 créé (vm_id 9001) !"
printf '\n'
printf '  Le template est maintenant disponible dans Proxmox.\n'
printf '  Tu peux lancer ./deploy.sh pour provisionner ad-dc1.\n'
printf '\n'
