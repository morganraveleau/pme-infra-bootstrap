#!/usr/bin/env bash
# =============================================================================
# Bootstrap Infra PME — Lanceur Linux / macOS
# Usage : ./start.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
error() { printf "${RED}[✗]${NC} %s\n" "$1"; exit 1; }

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║        Bootstrap Infra PME — Lanceur Linux/macOS        ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Vérifier Docker ───────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || error "Docker non installé.
  Linux : https://docs.docker.com/engine/install/
  macOS : https://www.docker.com/products/docker-desktop/"

docker info >/dev/null 2>&1 || error "Docker n'est pas démarré. Lance Docker Desktop ou 'sudo systemctl start docker'."

# ── Arrêter un conteneur existant ─────────────────────────────────────────────
docker stop pme-bootstrap 2>/dev/null && docker rm pme-bootstrap 2>/dev/null || true

# ── Build de l'image ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
warn "Construction de l'image Docker (1ère fois : 3-5 min)..."
docker build -t pme-bootstrap:latest "$SCRIPT_DIR"
info "Image construite."

# ── Ouvrir le navigateur ──────────────────────────────────────────────────────
echo ""
info "Démarrage du configurateur sur http://localhost:5000"
echo "   Pour arrêter : Ctrl+C"
echo ""

# Ouvrir le navigateur après 3 secondes
( sleep 3
  if command -v xdg-open >/dev/null; then xdg-open http://localhost:5000
  elif command -v open >/dev/null; then open http://localhost:5000
  fi ) &

# ── Démarrer le conteneur ─────────────────────────────────────────────────────
SSH_DIR="${HOME}/.ssh"
[[ -d "$SSH_DIR" ]] || mkdir -p "$SSH_DIR"

docker run --rm -it \
  -p 5000:5000 \
  -v "$SCRIPT_DIR":/workspace \
  -v "$SSH_DIR":/root/.ssh:ro \
  -e TF_DATA_DIR=/root/.terraform-data/pme-infra-bootstrap \
  --name pme-bootstrap \
  pme-bootstrap:latest
