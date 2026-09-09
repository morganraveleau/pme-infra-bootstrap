# Architecture V1

Résumé technique. La feuille de route jour par jour et le suivi de progression vivent dans la page dédiée (artifact "Bootstrap Infra PME") — ce document reste la référence versionnée dans le dépôt.

## Vue d'ensemble

```
Dépôt Git ──► Formulaire web (webapp-config) ──► tfvars.json + group_vars.yml
                                                        │
                                                        ▼
                                                    deploy.sh
                                                   /          \
                                      terraform apply       ansible-playbook
                                              │                     │
                                              ▼                     ▼
                                     2 VMs sur Proxmox      configure les VMs
```

Un seul hôte Proxmox VE. Deux VMs :

- **k3s-node1** (Debian 12) : control-plane + worker k3s en un seul noeud. Héberge en conteneurs : Traefik (ingress, fourni par k3s), l'appli web de démo (front+back), PostgreSQL, et kube-prometheus-stack (Prometheus + Grafana + Alertmanager).
- **ad-dc1** (Windows Server, éval 180 jours) : Active Directory Domain Services + DNS. WSUS est délibérément hors V1 (voir backlog).

## Budget ressources

| Composant | RAM | vCPU | Disque | Note |
|---|---|---|---|---|
| Proxmox (hôte) | 2 Go | — | — | overhead hyperviseur |
| VM k3s-node1 | 4 Go | 2 | 40 Go | control-plane + worker |
| VM ad-dc1 | 4 Go | 2 | 80 Go | Server Core conseillé |
| **Total** | **10 Go (+2 hôte)** | **4** | **120 Go** | tient sur 16 Go |

Sur 8 Go : redescendre k3s-node1 et ad-dc1 à 2 Go chacun, désactiver Alertmanager, réduire la rétention Prometheus à 6h.

## Pourquoi ces choix

- **k3s plutôt que kubeadm** : empreinte mémoire bien plus légère, un seul binaire, adapté à un homelab avec peu de RAM — sans sacrifier l'apprentissage Kubernetes (l'API et les objets sont les mêmes).
- **bpg/proxmox plutôt que telmate/proxmox** : provider Terraform le plus activement maintenu pour Proxmox VE en 2026.
- **Le formulaire génère des fichiers, il n'orchestre pas** : plus simple à livrer en V1, plus facile à déboguer (on peut relire/éditer les fichiers générés avant de lancer `deploy.sh`). L'orchestration directe est prévue en V2.
- **AD Windows réel (pas Samba4)** : décision volontaire pour coller aux usages réels des PME, malgré le coût en licence/ressources par rapport à une alternative open source. Utiliser l'ISO d'évaluation gratuite (180 jours) pour le labo.

## Backlog V2 / V3

- **WSUS** — 2ᵉ VM Windows dédiée, reportée : stockage lourd (30-100 Go) incompatible avec le budget RAM/temps de la V1.
- **k3s multi-node / HA** — nécessite plus de RAM que le budget V1.
- **Webapp orchestratrice** — lance elle-même terraform/ansible avec logs en direct, au lieu de seulement générer les fichiers.
- **Multi-provider** — modules Terraform interchangeables pour vCenter, AWS, Azure, GCP en plus de Proxmox.
- **Gestion des secrets** — Vault ou SOPS+age au lieu de mots de passe en clair dans les fichiers générés.
- **Tests automatisés** — Molecule (rôles Ansible), Terratest (modules Terraform).
- **Runner GitHub Actions auto-hébergé** — pour un vrai CD déclenché depuis GitHub, pas seulement du lint.
- **Option Samba4** — alternative légère et 100% open source à l'AD Windows pour les budgets serrés.
