#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Point d'entrée unique Bootstrap Infra PME
# Usage : ./deploy.sh
# Enchaîne : pré-requis → terraform init/apply → génération inventaire → ansible
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"

# WSL / NTFS : terraform ne peut pas faire chmod sur /mnt/c/...
# On stocke les providers sur le filesystem Linux natif pour éviter l'erreur.
export TF_DATA_DIR="${HOME}/.terraform-data/pme-infra-bootstrap"
mkdir -p "$TF_DATA_DIR"

log()  { printf '\n\033[1;33m==> %s\033[0m\n' "$1"; }
err()  { printf '\033[1;31mErreur : %s\033[0m\n' "$1" >&2; exit 1; }
info() { printf '    %s\n' "$1"; }

# =============================================================================
# 1. Pré-requis : vérifications et installations légères
# =============================================================================
log "Vérification des pré-requis"

command -v terraform        >/dev/null 2>&1 || err "terraform non trouvé — installe-le depuis https://developer.hashicorp.com/terraform"
command -v ansible-playbook >/dev/null 2>&1 || err "ansible-playbook non trouvé — pip install ansible"
command -v curl             >/dev/null 2>&1 || err "curl non trouvé"
command -v kubectl          >/dev/null 2>&1 || err "kubectl non trouvé — installe-le :
  Linux/WSL : curl -LO \"https://dl.k8s.io/release/\$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  macOS     : brew install kubectl
  Voir      : https://kubernetes.io/docs/tasks/tools/"

info "terraform   : $(terraform version -json | python3 -c 'import sys,json;print(json.load(sys.stdin)[\"terraform_version\"])')"
info "ansible     : $(ansible --version | head -1)"
info "kubectl     : $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"

# =============================================================================
# 2. Clé SSH dédiée au projet
# Utilisée par cloud-init pour injecter l'accès SSH dans les VMs Linux,
# et par Ansible pour s'y connecter.
# =============================================================================
log "Clé SSH projet"

SSH_KEY="${HOME}/.ssh/id_ed25519_bootstrap"

if [[ ! -f "$SSH_KEY" ]]; then
  info "Génération de la clé SSH dédiée : $SSH_KEY"
  ssh-keygen -t ed25519 -C "bootstrap-pme" -f "$SSH_KEY" -N ""
else
  info "Clé SSH existante : $SSH_KEY"
fi

# Exporter la clé publique comme variable Terraform (évite de la mettre dans les tfvars)
export TF_VAR_ssh_public_key
TF_VAR_ssh_public_key=$(cat "${SSH_KEY}.pub")

# =============================================================================
# 3. Fichier de variables Terraform
# =============================================================================
log "Vérification de terraform.tfvars.json"

if [[ ! -f "$TF_DIR/terraform.tfvars.json" ]] && [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
  err "Aucun fichier de variables Terraform trouvé.
Lance d'abord le formulaire (voir webapp-config/README.md)
ou copie terraform/terraform.tfvars.example en terraform/terraform.tfvars et remplis-le."
fi

# =============================================================================
# 4. Collections Ansible requises
# =============================================================================
log "Installation des collections Ansible"

ansible-galaxy collection install \
  kubernetes.core \
  ansible.windows \
  microsoft.ad \
  --force-with-deps 2>&1 | grep -E '(Installing|Skipping|error)' || true

# =============================================================================
# 5. Terraform : provisionner les VMs sur Proxmox
# =============================================================================
log "Terraform init"
terraform -chdir="$TF_DIR" init -input=false

log "Terraform plan"
terraform -chdir="$TF_DIR" plan -input=false -out=tfplan

log "Terraform apply (template Debian + k3s-node1 + ad-dc1)"
terraform -chdir="$TF_DIR" apply -input=false tfplan

# =============================================================================
# 6. Génération de l'inventaire Ansible depuis les outputs Terraform
# =============================================================================
log "Génération de l'inventaire Ansible"

K3S_IP=$(terraform -chdir="$TF_DIR" output -raw k3s_node1_ip)
AD_IP=$(terraform -chdir="$TF_DIR" output -raw ad_dc1_ip)

if [[ ! -f "$ANSIBLE_DIR/inventory/hosts.yml" ]]; then
  sed -e "s/192\.168\.1\.50/${K3S_IP}/" \
      -e "s/192\.168\.1\.51/${AD_IP}/" \
      "$ANSIBLE_DIR/inventory/hosts.yml.example" \
    > "$ANSIBLE_DIR/inventory/hosts.yml"
  info "Inventaire généré : ansible/inventory/hosts.yml"
  info "Vérifie les paramètres SSH/WinRM avant de continuer si nécessaire."
else
  info "Inventaire existant conservé : ansible/inventory/hosts.yml"
fi

# Injecter le chemin de la clé SSH dans l'inventaire si ce n'est pas déjà fait
if ! grep -q "id_ed25519_bootstrap" "$ANSIBLE_DIR/inventory/hosts.yml"; then
  sed -i "s|~/.ssh/id_ed25519_bootstrap|${SSH_KEY}|g" "$ANSIBLE_DIR/inventory/hosts.yml"
fi

# =============================================================================
# 7. Variables Ansible (group_vars)
# =============================================================================
if [[ ! -f "$ANSIBLE_DIR/group_vars/all.yml" ]]; then
  cp "$ANSIBLE_DIR/group_vars/all.yml.example" "$ANSIBLE_DIR/group_vars/all.yml"
  info "group_vars/all.yml créé depuis l'exemple — pense à changer les mots de passe !"
fi

# =============================================================================
# 8. Ansible : configurer les VMs
# =============================================================================
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

log "Ansible playbook"
ansible-playbook \
  -i "$ANSIBLE_DIR/inventory/hosts.yml" \
  --private-key "$SSH_KEY" \
  "$ANSIBLE_DIR/site.yml"

# =============================================================================
# Résultat
# =============================================================================
log "Déploiement terminé !"
printf '\n'
printf '  k3s-node1 : %s\n' "$K3S_IP"
printf '  ad-dc1    : %s\n' "$AD_IP"
printf '\n'
printf '  Grafana  → http://%s (ingress Traefik — configurer le DNS ou /etc/hosts)\n' "$K3S_IP"
printf '  Kubeconfig → %s/.kube/bootstrap-pme.yaml\n' "$HOME"
printf '\n'
