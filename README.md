# Bootstrap Infra PME

Automatisation complète du déploiement d'une infrastructure de petite entreprise sur un hyperviseur **Proxmox VE** existant. Un seul script (`deploy.sh`) provisionne les VMs via **Terraform**, les configure via **Ansible**, et déploie une stack applicative conteneurisée sur **k3s**.

L'ISO Windows est téléchargée automatiquement par Proxmox. Le template Windows est construit automatiquement par **Packer**. Aucune intervention manuelle sur le serveur Proxmox n'est requise.

---

## Table des matières

1. [Architecture](#architecture)
2. [Composants déployés](#composants-déployés)
3. [Prérequis](#prérequis)
4. [Structure du dépôt](#structure-du-dépôt)
5. [Configuration Proxmox (une seule fois)](#configuration-proxmox-une-seule-fois)
6. [Première utilisation — vue d'ensemble](#première-utilisation--vue-densemble)
7. [Étape 0 — Créer le template Windows avec Packer](#étape-0--créer-le-template-windows-avec-packer)
8. [Étape 1 — Déployer l'infrastructure avec deploy.sh](#étape-1--déployer-linfrastructure-avec-deploysh)
9. [Référence des variables](#référence-des-variables)
10. [Ce que fait chaque script en détail](#ce-que-fait-chaque-script-en-détail)
11. [Rôles Ansible](#rôles-ansible)
12. [Dépannage](#dépannage)
13. [Backlog et évolutions prévues](#backlog-et-évolutions-prévues)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Serveur Proxmox VE  (192.168.1.10)                                 │
│                                                                     │
│  ┌─────────────────────────────────┐  ┌────────────────────────┐   │
│  │  VM k3s-node1 (Debian 12)       │  │  VM ad-dc1 (Win 2022)  │   │
│  │  192.168.1.50                   │  │  192.168.1.51          │   │
│  │                                 │  │                        │   │
│  │  ┌─────────────────────────┐    │  │  AD DS + DNS           │   │
│  │  │  k3s (single-node)      │    │  │  acme.lab              │   │
│  │  │  ┌──────┐  ┌─────────┐  │    │  │                        │   │
│  │  │  │Webapp│  │Traefik  │  │    │  │  OUs :                 │   │
│  │  │  │Front │  │(ingress)│  │    │  │  • Utilisateurs        │   │
│  │  │  │Back  │  └─────────┘  │    │  │  • Ordinateurs-Postes  │   │
│  │  │  │Postgres              │    │  │  • Serveurs            │   │
│  │  │  └──────┘               │    │  │  • Groupes             │   │
│  │  │  ┌──────────────────┐   │    │  │                        │   │
│  │  │  │kube-prometheus   │   │    │  │  Groupes de sécurité   │   │
│  │  │  │Grafana·Prometheus│   │    │  │  Utilisateurs d'exemple│   │
│  │  │  │Alertmanager      │   │    │  │                        │   │
│  │  │  └──────────────────┘   │    │  └────────────────────────┘   │
│  │  └─────────────────────────┘    │                               │
│  └─────────────────────────────────┘                               │
│                                                                     │
│  Templates (créés automatiquement) :                                │
│  • vm_id 9000 — Debian 12 cloud-init (base des VMs Linux)          │
│  • vm_id 9001 — Windows Server 2022 + cloudbase-init (Packer)      │
└─────────────────────────────────────────────────────────────────────┘
```

**Flux de provisionnement :**

```
packer-build.sh                          deploy.sh
      │                                      │
      ├─ terraform apply -target ISO    ─────┤
      │    └─ Proxmox télécharge ISO         │
      │         (~5.4 Go depuis Microsoft)   ├─ terraform init / apply
      │                                      │    ├─ Télécharge image Debian 12
      ├─ packer build                        │    ├─ Crée template Debian (9000)
      │    ├─ Installe Windows               │    ├─ Clone k3s-node1 (Debian)
      │    ├─ VirtIO drivers                 │    └─ Clone ad-dc1 (Windows 9001)
      │    ├─ cloudbase-init                 │
      │    └─ sysprep → template 9001        ├─ ansible-playbook site.yml
      │                                      │    ├─ rôle k3s
            ↓ (fait une seule fois)          │    ├─ rôle webapp
                                             │    ├─ rôle monitoring
                                             │    └─ rôle ad_domain_controller
```

---

## Composants déployés

### VM k3s-node1 (Debian 12, 4 Go RAM, 2 vCPU, 40 Go)

| Composant | Rôle |
|---|---|
| **k3s** | Distribution Kubernetes légère — control-plane + worker sur un seul nœud |
| **Traefik** | Ingress controller (fourni avec k3s) — expose les services HTTP/HTTPS |
| **Webapp** | Application de démonstration (front-end + back-end) |
| **PostgreSQL** | Base de données de l'application |
| **Prometheus** | Collecte de métriques Kubernetes et applicatives |
| **Grafana** | Tableaux de bord — accessible via Traefik |
| **Alertmanager** | Gestion des alertes Prometheus |

### VM ad-dc1 (Windows Server 2022 Eval, 4 Go RAM, 2 vCPU, 80 Go)

| Composant | Rôle |
|---|---|
| **AD DS** | Active Directory Domain Services — annuaire centralisé |
| **DNS** | Résolution de noms du domaine (installé avec AD DS) |
| **cloudbase-init** | Équivalent Windows de cloud-init — configuration réseau au 1er boot |
| **WinRM HTTPS** | Gestion à distance via Ansible (port 5986) |

**Structure Active Directory créée automatiquement :**

```
DC=acme,DC=lab
└── OU=ACME
    ├── OU=Utilisateurs        (comptes utilisateurs du domaine)
    ├── OU=Ordinateurs-Postes  (postes de travail joints)
    ├── OU=Serveurs            (serveurs membres)
    └── OU=Groupes
        ├── GRP-Admins-SI
        ├── GRP-Utilisateurs
        ├── GRP-Direction
        └── GRP-Informatique
```

**Utilisateurs créés par défaut (mots de passe à changer en production) :**

| Identifiant | Groupes | Description |
|---|---|---|
| `admin.si` | GRP-Admins-SI, GRP-Informatique | Administrateur SI |
| `jean.dupont` | GRP-Utilisateurs | Utilisateur standard |
| `marie.martin` | GRP-Utilisateurs, GRP-Direction | Direction |

---

## Prérequis

### Sur la machine de déploiement (Linux ou WSL)

| Outil | Version min. | Installation |
|---|---|---|
| **Terraform** | 1.7.0 | https://developer.hashicorp.com/terraform |
| **Ansible** | 2.15 | `pip install ansible` |
| **kubectl** | dernière | Voir section Dépannage |
| **Packer** | 1.10.0 | https://developer.hashicorp.com/packer/downloads *(Étape 0 uniquement)* |
| **curl** | n'importe | fourni avec la plupart des distributions |

> **WSL :** toutes les commandes doivent être exécutées depuis un terminal WSL (Ubuntu/Debian), pas depuis PowerShell ni CMD. Le projet utilise `TF_DATA_DIR` pour stocker les providers Terraform sur le filesystem Linux natif et éviter les erreurs de permissions NTFS.

### Serveur Proxmox VE

- Version **8.x** recommandée
- Accès réseau depuis la machine de déploiement (port 8006 pour l'API, port 22 pour SSH)
- Un utilisateur API avec token (voir [Configuration Proxmox](#configuration-proxmox-une-seule-fois))
- Au moins **16 Go de RAM** disponibles sur l'hôte (12 Go pour les VMs + overhead Proxmox)
- Au moins **200 Go** de stockage disponible (`local-lvm` pour les disques VM, `local` pour les ISOs et templates)
- Connexion internet depuis le serveur Proxmox (pour télécharger l'ISO Windows et l'image Debian)

---

## Structure du dépôt

```
pme-infra-bootstrap/
│
├── deploy.sh                        ← Point d'entrée principal (terraform + ansible)
├── packer-build.sh                  ← Construction du template Windows (à faire avant deploy.sh)
│
├── terraform/                       ← Provisionnement des VMs sur Proxmox
│   ├── versions.tf                  ← Provider bpg/proxmox ~0.66
│   ├── variables.tf                 ← Toutes les variables avec descriptions
│   ├── main.tf                      ← Ressources : ISO Debian, template 9000, k3s-node1, ad-dc1, ISO Windows
│   ├── outputs.tf                   ← IPs des VMs, ID template, nom ISO Windows
│   ├── terraform.tfvars.example     ← Modèle à copier en terraform.tfvars
│   └── modules/
│       └── proxmox-vm/              ← Module réutilisable : clone d'un template Proxmox
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
│
├── packer/                          ← Construction du template Windows Server 2022
│   ├── windows-server-2022.pkr.hcl  ← Template Packer principal (builder proxmox-iso)
│   ├── variables.pkr.hcl            ← Déclarations des variables Packer
│   ├── windows-server-2022.pkrvars.hcl.example  ← Modèle à copier et remplir
│   ├── http/
│   │   └── autounattend.xml         ← Réponses Windows Setup (installation silencieuse)
│   └── scripts/
│       ├── 01-install-virtio.ps1    ← Drivers VirtIO (viostor, vioscsi, netkvm, balloon…)
│       ├── 02-install-cloudbase-init.ps1  ← cloudbase-init + config ConfigDriveV2
│       └── 03-finalize.ps1          ← WinRM HTTPS, nettoyage, sysprep → shutdown
│
├── ansible/                         ← Configuration des VMs après provisionnement
│   ├── ansible.cfg                  ← Config Ansible (inventaire, retries, timeouts)
│   ├── site.yml                     ← Playbook principal — appelle tous les rôles
│   ├── requirements.yml             ← Collections : kubernetes.core, ansible.windows, microsoft.ad
│   ├── group_vars/
│   │   └── all.yml.example          ← Variables globales Ansible (domaine AD, mots de passe…)
│   ├── inventory/
│   │   └── hosts.yml.example        ← Inventaire : k3s (SSH) + active_directory (WinRM HTTPS)
│   └── roles/
│       ├── k3s/                     ← Installation k3s + kubeconfig
│       ├── webapp/                  ← Déploiement de la stack applicative (Kubernetes manifests)
│       ├── monitoring/              ← kube-prometheus-stack via Helm
│       └── ad_domain_controller/    ← Active Directory complet (5 étapes)
│           ├── defaults/main.yml    ← OUs, groupes et utilisateurs par défaut
│           ├── handlers/main.yml    ← Reboots post-install et post-promotion
│           └── tasks/
│               ├── main.yml         ← Orchestration avec tags
│               ├── 01_install_adds.yml    ← win_feature AD-Domain-Services
│               ├── 02_promote_dc.yml      ← Promotion DC + wait loop
│               ├── 03_ou_structure.yml    ← Création des OUs
│               ├── 04_groups.yml          ← Groupes de sécurité
│               └── 05_users.yml           ← Utilisateurs + affectation groupes
│
├── webapp-config/                   ← Formulaire web pour générer les fichiers de config
│   ├── app.py                       ← Serveur Flask (localhost:5000)
│   ├── requirements.txt
│   └── templates/
│       ├── form.html                ← Formulaire de configuration
│       └── done.html                ← Page de confirmation
│
├── docs/
│   └── architecture.md              ← Choix techniques, budget ressources, backlog
│
├── .gitignore                       ← Exclut : tfvars, state, secrets, inventaire réel
└── LICENSE
```

---

## Configuration Proxmox (une seule fois)

### 1. Créer un utilisateur et un token API Terraform

Dans l'interface Proxmox (`https://192.168.1.10:8006`) :

**Datacenter → Permissions → Users → Add**
- User : `terraform@pve`
- Realm : `Proxmox VE authentication server`

**Datacenter → Permissions → API Tokens → Add**
- User : `terraform@pve`
- Token ID : `terraform-token`
- **Décocher "Privilege Separation"** (le token hérite des droits de l'utilisateur)
- **Copier le secret affiché** — il n'est visible qu'une seule fois

**Datacenter → Permissions → Add → User Permission**
- Path : `/`
- User : `terraform@pve`
- Role : `Administrator` *(ou un rôle personnalisé avec VM.Allocate, VM.Config.*, Datastore.AllocateSpace, Datastore.Audit, SDN.Use, Sys.Audit)*

### 2. Activer SSH root sur le nœud Proxmox

Le provider `bpg/proxmox` utilise SSH pour importer les disques cloud-init. SSH root est activé par défaut sur Proxmox — vérifier dans `/etc/ssh/sshd_config` que `PermitRootLogin yes` est présent.

Copier la clé SSH publique de la machine de déploiement vers Proxmox :

```bash
ssh-copy-id root@192.168.1.10
```

### 3. Vérifier la connectivité

```bash
# Tester l'API Proxmox
curl -k -s "https://192.168.1.10:8006/api2/json/version" | python3 -m json.tool

# Tester SSH
ssh root@192.168.1.10 "hostname && pveversion"
```

---

## Première utilisation — vue d'ensemble

```
┌──────────────────────────────────────────────────────────┐
│  ORDRE OBLIGATOIRE                                       │
│                                                          │
│  1.  Configurer Proxmox (token API + SSH) ─── une fois  │
│  2.  Remplir les fichiers de config           ─── une fois  │
│  3.  ./packer-build.sh   (template Windows)  ─── une fois  │
│  4.  ./deploy.sh         (tout le reste)     ─── répétable │
└──────────────────────────────────────────────────────────┘
```

`packer-build.sh` ne doit être lancé qu'une fois. Il crée le template Windows (`vm_id 9001`) dans Proxmox. Ensuite, `deploy.sh` clone ce template pour créer la VM AD à chaque déploiement.

---

## Étape 0 — Créer le template Windows avec Packer

### 0.1 Remplir le fichier de variables Packer

```bash
cp packer/windows-server-2022.pkrvars.hcl.example packer/windows-server-2022.pkrvars.hcl
```

Éditer `packer/windows-server-2022.pkrvars.hcl` :

```hcl
pm_api_url          = "https://192.168.1.10:8006/api2/json"
pm_api_token_id     = "terraform@pve!terraform-token"
pm_api_token_secret = "le-secret-du-token"
pm_node             = "pve"
network_bridge      = "vmbr0"
datastore           = "local-lvm"

# Rempli automatiquement par packer-build.sh via terraform output
# (ne pas modifier)
windows_iso_file = "Windows_Server_2022_x64_EN_Eval.iso"

# Mot de passe utilisé UNIQUEMENT pendant le build Packer
# Cloudbase-init le réinitialise au 1er boot des VMs clonées
windows_admin_password = "Packer2024!"
```

> **Note :** `windows_iso_file` est renseigné automatiquement par `packer-build.sh`. La valeur ci-dessus sert uniquement de référence.

### 0.2 S'assurer que terraform.tfvars est rempli

`packer-build.sh` utilise Terraform pour déclencher le téléchargement de l'ISO. Le fichier `terraform/terraform.tfvars` doit donc exister (voir Étape 1.1).

### 0.3 Lancer le build

```bash
./packer-build.sh
```

**Ce que fait ce script, dans l'ordre :**

1. **Vérifie** que `terraform` et `packer` sont installés
2. **`terraform apply -target=proxmox_download_file.windows_server_2022_iso`** — Proxmox télécharge l'ISO Windows Server 2022 (~5.4 Go) directement depuis les serveurs Microsoft. La progression est visible dans l'interface Proxmox (Datacenter → Tasks). Si le fichier existe déjà, cette étape est instantanée.
3. **`terraform output windows_server_2022_iso_filename`** — récupère le nom du fichier ISO
4. **`packer init`** — télécharge le plugin Packer pour Proxmox si absent
5. **`packer validate`** — vérifie la syntaxe du template
6. **`packer build`** — crée une VM temporaire dans Proxmox, installe Windows depuis l'ISO, puis :
   - Windows s'installe silencieusement via `autounattend.xml` (aucune interaction requise)
   - Packer attend la disponibilité de WinRM (jusqu'à 2h — l'installation Windows prend 15-25 min)
   - `01-install-virtio.ps1` : installe les drivers VirtIO (réseau, disque, ballon mémoire…)
   - Redémarrage
   - `02-install-cloudbase-init.ps1` : installe cloudbase-init (configuration réseau au clone)
   - `03-finalize.ps1` : configure WinRM HTTPS (port 5986), nettoie, lance sysprep → arrêt
   - Proxmox convertit la VM en template (`vm_id 9001`)

**Durée totale :** 10-20 min (ISO) + 30-45 min (build Windows) = **~1h**

> La VM temporaire créée par Packer est visible dans l'interface Proxmox pendant le build. Elle disparaît et devient le template à la fin.

---

## Étape 1 — Déployer l'infrastructure avec deploy.sh

### 1.1 Remplir les variables Terraform

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Éditer `terraform/terraform.tfvars` :

```hcl
# Connexion Proxmox
pm_api_url              = "https://192.168.1.10:8006/api2/json"
pm_api_token_id         = "terraform@pve!terraform-token"
pm_api_token_secret     = "le-secret-du-token"
pm_node                 = "pve"
pm_node_address         = "192.168.1.10"
pm_ssh_private_key_path = "~/.ssh/id_ed25519"  # ou id_rsa

# Paramètres généraux
company_name   = "acme"       # préfixe des noms de VMs
network_bridge = "vmbr0"
datastore      = "local-lvm"

# VM k3s (Debian 12, cloud-init)
k3s_vm = {
  vcpu       = 2
  memory_mb  = 4096
  disk_gb    = 40
  ip_address = "192.168.1.50/24"
  gateway    = "192.168.1.254"
}

# VM Active Directory (Windows Server 2022)
ad_vm = {
  template_id = 9001           # template créé par packer-build.sh
  vcpu        = 2
  memory_mb   = 4096
  disk_gb     = 80
  ip_address  = "192.168.1.51/24"
  gateway     = "192.168.1.254"
}
```

> **`ssh_public_key`** : inutile de la définir ici. `deploy.sh` génère automatiquement `~/.ssh/id_ed25519_bootstrap` si elle n'existe pas et exporte `TF_VAR_ssh_public_key`.

### 1.2 Remplir les variables Ansible

```bash
cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml
```

Éditer `ansible/group_vars/all.yml` :

```yaml
company_name: "acme"

# Stack applicative
webapp_domain: "app.acme.lab"
webapp_enable_monitoring: true
postgres_db_name: "acme_app"
postgres_admin_password: "MonMotDePassePostgres!"

# Active Directory
ad_domain_name: "acme.lab"
ad_domain_netbios_name: "ACME"
ad_safe_mode_admin_password: "MonMotDePasseDSRM!"  # complexité Windows requise

# Mot de passe du compte Administrator Windows
# Doit correspondre à windows_admin_password dans le fichier pkrvars
vault_windows_admin_password: "Packer2024!"

# Monitoring
grafana_admin_password: "MonMotDePasseGrafana!"
prometheus_retention: "15d"
```

> **Conseil :** chiffrer les mots de passe avec `ansible-vault` en production :
> ```bash
> ansible-vault encrypt_string 'MonMotDePasse!' --name 'vault_windows_admin_password'
> ```
> Puis ajouter `--ask-vault-pass` à la commande Ansible dans `deploy.sh`.

### 1.3 Lancer le déploiement

```bash
./deploy.sh
```

**Ce que fait ce script, dans l'ordre :**

1. **Prérequis** : vérifie que `terraform`, `ansible-playbook`, `curl`, `kubectl` sont installés
2. **Clé SSH** : génère `~/.ssh/id_ed25519_bootstrap` si elle n'existe pas — utilisée par cloud-init (injection dans les VMs Linux) et par Ansible (connexion SSH)
3. **Variables Terraform** : vérifie la présence de `terraform.tfvars` ou `terraform.tfvars.json`
4. **Collections Ansible** : installe `kubernetes.core`, `ansible.windows`, `microsoft.ad` via `ansible-galaxy`
5. **`terraform init`** : télécharge le provider `bpg/proxmox`
6. **`terraform plan`** : calcule les changements
7. **`terraform apply`** : crée en parallèle :
   - Le template Debian 12 cloud-init (`vm_id 9000`) — télécharge l'image cloud Debian
   - La VM `acme-k3s-node1` — clone du template Debian
   - La VM `acme-ad-dc1` — clone du template Windows (`vm_id 9001`)
8. **Génération de l'inventaire** : crée `ansible/inventory/hosts.yml` avec les IPs sorties de `terraform output`
9. **Copie de `group_vars/all.yml`** : depuis l'exemple si le fichier n'existe pas encore
10. **`ansible-playbook site.yml`** : configure les VMs (détail par rôle ci-dessous)

**Durée totale :** 5-10 min (Terraform) + 20-40 min (Ansible) = **~45 min**

---

## Référence des variables

### Terraform — `terraform/variables.tf`

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `pm_api_url` | string | — | URL de l'API Proxmox `https://<IP>:8006/api2/json` |
| `pm_api_token_id` | string | — | ID du token `terraform@pve!terraform-token` |
| `pm_api_token_secret` | string | — | Secret du token (sensible) |
| `pm_node` | string | — | Nom du nœud Proxmox (ex: `pve`) |
| `pm_node_address` | string | `192.168.1.10` | IP du nœud (pour SSH provider) |
| `pm_ssh_private_key_path` | string | `~/.ssh/id_ed25519` | Clé privée SSH root Proxmox |
| `company_name` | string | `acme` | Préfixe des noms de VMs |
| `network_bridge` | string | `vmbr0` | Bridge réseau Proxmox |
| `datastore` | string | `local-lvm` | Stockage pour les disques VM |
| `ssh_public_key` | string | — | Clé publique SSH (auto-exportée par deploy.sh) |
| `k3s_vm` | object | — | `vcpu`, `memory_mb`, `disk_gb`, `ip_address`, `gateway` |
| `ad_vm` | object | — | `template_id`, `vcpu`, `memory_mb`, `disk_gb`, `ip_address`, `gateway` |
| `windows_iso_url` | string | *(URL Microsoft)* | URL de l'ISO Windows Server 2022 Eval |

### Ansible — `ansible/group_vars/all.yml`

| Variable | Description |
|---|---|
| `company_name` | Nom de la PME (utilisé dans le nom de l'OU racine AD) |
| `webapp_domain` | Domaine de l'application web (ex: `app.acme.lab`) |
| `webapp_enable_monitoring` | Active le déploiement de kube-prometheus-stack |
| `postgres_db_name` | Nom de la base PostgreSQL |
| `postgres_admin_password` | Mot de passe PostgreSQL |
| `ad_domain_name` | FQDN du domaine AD (ex: `acme.lab`) |
| `ad_domain_netbios_name` | Nom NetBIOS (ex: `ACME`) |
| `ad_safe_mode_admin_password` | Mot de passe DSRM (récupération AD) |
| `vault_windows_admin_password` | Mot de passe Administrator Windows (WinRM) |
| `grafana_admin_password` | Mot de passe admin Grafana |
| `prometheus_retention` | Rétention des métriques (ex: `15d`, `6h`) |

### Ansible AD — `ansible/roles/ad_domain_controller/defaults/main.yml`

Ces variables ont des valeurs par défaut et peuvent être surchargées dans `group_vars/all.yml`.

| Variable | Description |
|---|---|
| `ad_dc` | Suffixe DN calculé depuis `ad_domain_name` (ex: `DC=acme,DC=lab`) |
| `ad_ou_company` | Nom de l'OU racine — hérite de `company_name` en majuscules |
| `ad_ou_children` | Liste des OUs enfants à créer |
| `ad_groups` | Liste des groupes de sécurité (nom, description, OU cible) |
| `ad_users` | Liste des utilisateurs (prénom, nom, login, mot de passe, groupes, OU) |

### Packer — `packer/windows-server-2022.pkrvars.hcl`

| Variable | Description |
|---|---|
| `pm_api_url` | URL API Proxmox |
| `pm_api_token_id` | Token API (mêmes droits que Terraform) |
| `pm_api_token_secret` | Secret du token |
| `pm_node` | Nœud Proxmox cible |
| `network_bridge` | Bridge réseau |
| `datastore` | Stockage pour le disque de la VM de build |
| `windows_iso_file` | Nom du fichier ISO dans Proxmox (rempli automatiquement) |
| `windows_admin_password` | Mot de passe Administrator pendant le build uniquement |

---

## Ce que fait chaque script en détail

### `packer/http/autounattend.xml`

Répond automatiquement à toutes les questions de Windows Setup :

- **Partition** : layout BIOS/MBR — 500 Mo système (active) + reste → C:
- **Édition** : Windows Server 2022 Standard Desktop Experience (clé KMS setup `VDYBN-27WPP-V4HQT-9VMD4-VMK7H` — sélectionne l'édition depuis l'ISO d'évaluation, ce n'est pas une clé d'activation)
- **Locales** : interface en anglais (`en-US`), saisie clavier français (`fr-FR`), fuseau horaire `Romance Standard Time` (Paris)
- **Compte** : Administrator avec le mot de passe défini dans `pkrvars`
- **WinRM** : activé dès le premier boot via `FirstLogonCommands` (winrm quickconfig, AllowUnencrypted, Basic, firewall port 5985)

### `packer/scripts/01-install-virtio.ps1`

Installe les drivers VirtIO depuis l'ISO montée sur un lecteur secondaire. Drivers installés : `viostor` (disque SCSI), `vioscsi`, `netkvm` (réseau VirtIO), `balloon` (gestion mémoire), `vioserial`, `vioser`, `vioinput`, `pvpanic`, `qxldod` (affichage). Installe également le QEMU Guest Agent (`qemu-ga-x86_64.msi`).

> **Pourquoi les drivers sont installés après Windows ?** Pendant le build Packer, la VM utilise un disque SATA et une carte réseau E1000 pour ne pas avoir besoin des drivers VirtIO pour démarrer. Une fois les drivers installés, les VMs clonées depuis le template peuvent utiliser VirtIO (plus performant).

### `packer/scripts/02-install-cloudbase-init.ps1`

Installe cloudbase-init (équivalent Windows de cloud-init) et le configure avec le datasource `ConfigDriveV2` compatible Proxmox. cloudbase-init s'exécute au premier boot de chaque VM clonée et configure : le nom d'hôte, l'adresse IP statique, le mot de passe Administrator.

### `packer/scripts/03-finalize.ps1`

- Crée un certificat auto-signé valable 10 ans pour WinRM HTTPS (port 5986)
- Configure les règles de pare-feu Windows (WinRM HTTP 5985, WinRM HTTPS 5986, RDP 3389)
- Désactive les mises à jour automatiques (pour stabiliser le template)
- Nettoie `%TEMP%`, `C:\Windows\Temp`, les journaux d'événements
- Lance `sysprep /oobe /generalize /quiet /shutdown` (généralise l'image, arrête la VM)
- Proxmox détecte l'arrêt et convertit la VM en template

---

## Rôles Ansible

### `roles/k3s`

Installe k3s en mode single-node sur Debian 12. Configure le kubeconfig dans `~/.kube/bootstrap-pme.yaml` sur la machine de déploiement.

### `roles/webapp`

Déploie via `kubectl apply` la stack applicative : Deployment front-end, Deployment back-end, StatefulSet PostgreSQL, Services, Ingress Traefik. Les manifests sont générés depuis le template `webapp-stack.yml.j2` avec les variables `group_vars/all.yml`.

### `roles/monitoring`

Déploie `kube-prometheus-stack` via Helm. Compose de Prometheus, Grafana, Alertmanager et les exporteurs standards Kubernetes. Grafana est exposé via Traefik sur `monitoring.<webapp_domain>`.

### `roles/ad_domain_controller`

Déploiement en 5 étapes, chacune taggée pour pouvoir les rejouer indépendamment :

```bash
# Rejouer uniquement la création des utilisateurs
ansible-playbook -i ansible/inventory/hosts.yml ansible/site.yml --tags ad_users

# Rejouer toute la configuration AD
ansible-playbook -i ansible/inventory/hosts.yml ansible/site.yml --tags ad
```

| Tag | Étape |
|---|---|
| `ad_install` | Installation AD DS + reboot si nécessaire |
| `ad_promote` | Promotion DC, attente AD disponible |
| `ad_ou` | Création des OUs |
| `ad_groups` | Création des groupes de sécurité |
| `ad_users` | Création des utilisateurs + affectation aux groupes |

Le rôle est **idempotent** : relancé sur un DC déjà promu, il détecte le domaine existant et saute la promotion. Les OUs, groupes et utilisateurs déjà présents ne sont pas recréés.

---

## Dépannage

### `kubectl` non trouvé

```bash
# Linux / WSL
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# macOS
brew install kubectl
```

### Erreur Terraform `chmod` ou `permission denied` sous WSL

`deploy.sh` exporte automatiquement `TF_DATA_DIR` vers un dossier sur le filesystem Linux natif. Si l'erreur persiste, exécuter manuellement :

```bash
export TF_DATA_DIR="${HOME}/.terraform-data/pme-infra-bootstrap"
mkdir -p "$TF_DATA_DIR"
```

### L'ISO Windows expire ou le téléchargement échoue

L'URL de l'ISO Microsoft Evaluation change périodiquement. Récupérer la nouvelle URL sur [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) et la mettre à jour dans `terraform/variables.tf` (variable `windows_iso_url`, valeur `default`).

### Packer ne peut pas se connecter via WinRM (timeout)

Vérifier dans l'interface Proxmox que la VM temporaire Packer a démarré et que Windows s'installe. Les causes courantes :

- **VNC** : se connecter à la console de la VM dans Proxmox pour voir si l'installation Windows est bloquée
- **Réseau** : vérifier que la VM a bien obtenu une IP (ou que l'IP statique est correcte)
- **Pare-feu** : le port WinRM 5985 doit être accessible depuis la machine qui exécute Packer
- **autounattend.xml** : si Windows demande une interaction manuelle, c'est que le fichier n'a pas été détecté — vérifier que le CD `AUTOUNATTEND` est bien monté sur `ide2`

### WinRM NTLM échoue depuis Ansible

```bash
# Tester la connectivité WinRM depuis la machine de déploiement
pip install pywinrm
python3 -c "
import winrm
s = winrm.Session('https://192.168.1.51:5986/wsman',
    auth=('Administrator', 'Packer2024!'),
    transport='ntlm',
    server_cert_validation='ignore')
r = s.run_cmd('hostname')
print(r.std_out)
"
```

### Avertissement `VM.GuestAgent.Audit` dans Terraform

Ce warning apparaît si le token API Proxmox n'a pas la permission `VM.GuestAgent.Audit`. Il est cosmétique et n'empêche pas le déploiement. Pour le supprimer, ajouter cette permission au rôle du token dans Proxmox.

### `src refspec main does not match any` lors du push Git

La branche locale se nomme `master`. Utiliser :

```bash
git push origin master:main --force
```

### Terraform state corrompu ou VMs orphelines

```bash
# Lister les ressources dans le state
terraform -chdir=terraform state list

# Supprimer une ressource du state sans la détruire dans Proxmox
terraform -chdir=terraform state rm module.k3s_node1

# Importer une VM Proxmox existante dans le state
terraform -chdir=terraform import module.k3s_node1.proxmox_virtual_environment_vm.vm pve/qemu/100
```

---

## Backlog et évolutions prévues

Voir `docs/architecture.md` pour le détail. En résumé :

| Priorité | Fonctionnalité | Raison du report |
|---|---|---|
| V2 | **WSUS** — VM Windows dédiée aux mises à jour | Stockage lourd (30-100 Go) incompatible V1 |
| V2 | **Webapp orchestratrice** — lance terraform/ansible avec logs en direct | Complexité V1 |
| V2 | **k3s multi-node / HA** | Nécessite plus de RAM |
| V2 | **Gestion des secrets** — HashiCorp Vault ou SOPS+age | Simplifie V1 |
| V3 | **Tests automatisés** — Molecule (Ansible), Terratest (Terraform) | |
| V3 | **Runner GitHub Actions auto-hébergé** | CD depuis GitHub |
| V3 | **Multi-provider** — modules vCenter, AWS, Azure, GCP | |
| Option | **Samba4** — alternative open source à l'AD Windows | Pour les budgets serrés |

---

## Licence

MIT — voir `LICENSE`.
