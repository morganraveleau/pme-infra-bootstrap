"""
Formulaire web minimal (roadmap J11-J12).

Rôle volontairement limité en V1 : collecter la config de la PME et écrire
les deux fichiers que Terraform et Ansible consomment ensuite. Il ne lance
PAS terraform/ansible lui-même — c'est deploy.sh qui s'en charge (V2 : faire
lancer le déploiement directement par la webapp, avec les logs en direct).
"""

import json
import os
from pathlib import Path

from flask import Flask, render_template, request, redirect, url_for

app = Flask(__name__)

ROOT = Path(__file__).resolve().parent.parent
TF_OUTPUT = ROOT / "terraform" / "terraform.tfvars.json"
ANSIBLE_OUTPUT = ROOT / "ansible" / "group_vars" / "all.yml"


@app.route("/", methods=["GET"])
def form():
    return render_template("form.html")


@app.route("/generate", methods=["POST"])
def generate():
    f = request.form

    tfvars = {
        "pm_api_url": f["pm_api_url"],
        "pm_api_token_id": f["pm_api_token_id"],
        "pm_api_token_secret": f["pm_api_token_secret"],
        "pm_node": f["pm_node"],
        "company_name": f["company_name"],
        "network_bridge": f.get("network_bridge", "vmbr0"),
        "k3s_vm": {
            "template_id": int(f["k3s_template_id"]),
            "vcpu": int(f.get("k3s_vcpu", 2)),
            "memory_mb": int(f.get("k3s_memory_mb", 4096)),
            "disk_gb": int(f.get("k3s_disk_gb", 40)),
            "ip_address": f["k3s_ip_address"],
            "gateway": f["k3s_gateway"],
        },
        "ad_vm": {
            "template_id": int(f["ad_template_id"]),
            "vcpu": int(f.get("ad_vcpu", 2)),
            "memory_mb": int(f.get("ad_memory_mb", 4096)),
            "disk_gb": int(f.get("ad_disk_gb", 80)),
            "ip_address": f["ad_ip_address"],
            "gateway": f["ad_gateway"],
        },
    }

    TF_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    TF_OUTPUT.write_text(json.dumps(tfvars, indent=2, ensure_ascii=False))

    ansible_vars = f"""\
# Généré automatiquement par webapp-config/app.py — ne pas éditer à la main,
# relance le formulaire pour modifier ces valeurs.

company_name: "{f['company_name']}"

webapp_domain: "{f['webapp_domain']}"
webapp_enable_monitoring: {str(f.get('enable_monitoring') == 'on').lower()}
postgres_db_name: "{f['postgres_db_name']}"
postgres_admin_password: "{f['postgres_admin_password']}"

ad_domain_name: "{f['ad_domain_name']}"
ad_domain_netbios_name: "{f['ad_domain_netbios_name']}"
ad_safe_mode_admin_password: "{f['ad_safe_mode_admin_password']}"

grafana_admin_password: "{f['grafana_admin_password']}"
prometheus_retention: "{f.get('prometheus_retention', '6h')}"
"""
    ANSIBLE_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    ANSIBLE_OUTPUT.write_text(ansible_vars)

    return redirect(url_for("done"))


@app.route("/done", methods=["GET"])
def done():
    return render_template(
        "done.html",
        tf_path=TF_OUTPUT.relative_to(ROOT),
        ansible_path=ANSIBLE_OUTPUT.relative_to(ROOT),
    )


if __name__ == "__main__":
    app.run(debug=True, host="127.0.0.1", port=5000)
