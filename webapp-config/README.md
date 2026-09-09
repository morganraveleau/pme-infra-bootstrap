# webapp-config

Petit formulaire web (Flask) qui génère la configuration consommée par Terraform et Ansible. Volontairement minimal en V1 : pas de base de données, pas d'authentification, pas d'appel direct à terraform/ansible (ça, c'est `../deploy.sh`).

## Lancer en local

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Puis ouvrir http://localhost:5000.

## V2

Transformer ce formulaire en webapp orchestratrice : bouton "Déployer" qui lance `terraform apply` et le playbook Ansible via `subprocess`, avec les logs streamés dans le navigateur (ex: via Server-Sent Events).
