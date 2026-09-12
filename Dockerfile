# =============================================================================
# Bootstrap Infra PME — Image Docker tout-en-un
# Contient : Terraform, Packer, Ansible, kubectl, Python (Flask)
# Usage : docker build -t pme-bootstrap . && docker run -p 5000:5000 pme-bootstrap
# =============================================================================
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Dépendances système ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git unzip gnupg lsb-release software-properties-common \
    python3 python3-pip openssh-client sshpass jq \
    && rm -rf /var/lib/apt/lists/*

# ── HashiCorp (Terraform + Packer) ───────────────────────────────────────────
RUN wget -O /usr/share/keyrings/hashicorp.gpg \
      https://apt.releases.hashicorp.com/gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y terraform packer && \
    rm -rf /var/lib/apt/lists/*

# ── kubectl ───────────────────────────────────────────────────────────────────
RUN KVER=$(curl -sL https://dl.k8s.io/release/stable.txt) && \
    curl -sLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" && \
    chmod +x /usr/local/bin/kubectl

# ── Ansible + dépendances Python ─────────────────────────────────────────────
RUN pip3 install --no-cache-dir \
    ansible \
    pywinrm \
    requests \
    flask \
    python-pptx

# ── Collections Ansible requises par le projet ────────────────────────────────
RUN ansible-galaxy collection install \
    kubernetes.core \
    ansible.windows \
    microsoft.ad \
    --force

# ── Dossier de travail ────────────────────────────────────────────────────────
WORKDIR /workspace

# Copier le projet (sera écrasé par le volume mount en développement)
COPY . .

# TF_DATA_DIR sur le FS Linux natif (évite les erreurs chmod si volume Windows)
ENV TF_DATA_DIR=/root/.terraform-data/pme-infra-bootstrap

EXPOSE 5000

CMD ["python3", "webapp-config/app.py"]
