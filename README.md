# Bootstrap Infra PME

> Objectif : n'importe quelle PME clone ce dépôt, remplit un formulaire de config, lance une commande, et récupère une infra complète (k3s + applis + supervision + annuaire) sur Proxmox.

**Statut : V1 en cours de construction.** Ce dépôt est un projet personnel de montée en compétence DevOps (Terraform, Ansible, Kubernetes). La feuille de route détaillée (planning jour par jour, architecture, definition of done) est suivie séparément — voir `docs/architecture.md` pour le résumé technique.

## Ce que la V1 fait

Sur un hôte Proxmox VE unique, à partir d'un formulaire web rempli une fois :

1. **Terraform** provisionne deux VMs depuis des templates cloud-init : `k3s-node1` (Debian 12) et `ad-dc1` (Windows Server).
2. **Ansible** configure ensuite ces VMs :
   - installe k3s sur `k3s-node1` ;
   - déploie une stack applicative de démo (front + back + PostgreSQL) et `kube-prometheus-stack` (Prometheus/Grafana) dans k3s ;
   - installe le rôle AD DS sur `ad-dc1` et le promeut contrôleur de domaine.
3. Le tout est déclenché par un seul script : `./deploy.sh`.

Ce que la V1 **ne fait pas encore** (volontairement, voir `docs/architecture.md#backlog`) : WSUS, k3s multi-node, support d'autres hyperviseurs/clouds (vCenter, AWS, Azure, GCP), gestion des secrets via Vault/SOPS, tests automatisés.

## Prérequis

- Un hôte Proxmox VE joignable en réseau (8 Go de RAM minimum, 16 Go recommandés — voir le budget ressources dans `docs/architecture.md`).
- Un template cloud-init Debian 12 et un template Windows Server déjà présents sur Proxmox (voir `docs/architecture.md` pour les créer à la main la première fois).
- En local : Terraform ≥ 1.7, Ansible ≥ 2.15, Python ≥ 3.10.
- Un jeton API Proxmox (rôle avec droits de création de VM).

## Démarrage rapide

```bash
git clone <url-de-ton-fork> pme-infra-bootstrap
cd pme-infra-bootstrap

# 1. Remplir la config via le petit formulaire web
cd webapp-config
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py
# ouvrir http://localhost:5000, remplir le formulaire
# -> génère terraform/terraform.tfvars.json et ansible/group_vars/all.yml

# 2. Tout déployer
cd ..
./deploy.sh
```

## Structure du dépôt

```
terraform/          Provisioning des VMs (module réutilisable proxmox-vm)
ansible/             Configuration des VMs (rôles k3s, webapp, monitoring, ad_domain_controller)
webapp-config/       Petit formulaire web qui génère la config à partir des réponses
docs/                Architecture, budget ressources, décisions
.github/workflows/   Lint CI (terraform fmt/validate, ansible-lint, yamllint)
```

## Licence

MIT — voir `LICENSE`. Projet personnel, fourni tel quel, sans garantie de production.
