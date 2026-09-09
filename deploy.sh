#!/usr/bin/env bash
# Point d'entrée unique de la V1 (roadmap J13).
# Enchaîne : terraform init/apply -> génération inventaire -> ansible-playbook.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"

log() { printf '\n\033[1;33m==> %s\033[0m\n' "$1"; }

if [[ ! -f "$TF_DIR/terraform.tfvars.json" ]]; then
  echo "Erreur : $TF_DIR/terraform.tfvars.json introuvable." >&2
  echo "Lance d'abord le formulaire (voir webapp-config/README.md) ou copie terraform.tfvars.example." >&2
  exit 1
fi

log "Terraform init"
terraform -chdir="$TF_DIR" init -input=false

log "Terraform apply (provisionne k3s-node1 et ad-dc1 sur Proxmox)"
terraform -chdir="$TF_DIR" apply -auto-approve -input=false

log "Génération de l'inventaire Ansible depuis les outputs Terraform"
K3S_IP=$(terraform -chdir="$TF_DIR" output -raw k3s_node1_ip)
AD_IP=$(terraform -chdir="$TF_DIR" output -raw ad_dc1_ip)

if [[ ! -f "$ANSIBLE_DIR/inventory/hosts.yml" ]]; then
  sed -e "s/192.168.1.50/${K3S_IP}/" \
      -e "s/192.168.1.51/${AD_IP}/" \
      "$ANSIBLE_DIR/inventory/hosts.yml.example" > "$ANSIBLE_DIR/inventory/hosts.yml"
  echo "Inventaire généré : ansible/inventory/hosts.yml (vérifie les identifiants SSH/WinRM avant de continuer)"
fi

log "Ansible playbook (configure k3s, déploie applis+monitoring, promeut l'AD)"
ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.yml" "$ANSIBLE_DIR/site.yml"

log "Terminé. Grafana et l'appli sont accessibles via l'ingress Traefik du noeud k3s (${K3S_IP})."
