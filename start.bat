@echo off
chcp 65001 >nul
title Bootstrap Infra PME

echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║          Bootstrap Infra PME — Lanceur Windows          ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.

:: ── Vérifier Docker ──────────────────────────────────────────────────────────
where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERREUR] Docker Desktop n'est pas installe.
    echo.
    echo  Installer Docker Desktop depuis :
    echo  https://www.docker.com/products/docker-desktop/
    echo.
    pause
    exit /b 1
)

docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERREUR] Docker Desktop n'est pas demarre.
    echo  Ouvrir Docker Desktop, attendre qu'il soit pret, puis relancer ce script.
    echo.
    pause
    exit /b 1
)

:: ── Arrêter un conteneur existant ────────────────────────────────────────────
docker stop pme-bootstrap >nul 2>&1
docker rm pme-bootstrap >nul 2>&1

:: ── Build de l'image ─────────────────────────────────────────────────────────
echo  [1/2] Construction de l'image Docker (1ere fois : 3-5 min)...
echo        Les lancements suivants seront instantanes.
echo.
docker build -t pme-bootstrap:latest "%~dp0"
if %errorlevel% neq 0 (
    echo.
    echo  [ERREUR] La construction de l'image a echoue.
    echo  Verifiez votre connexion internet et que Docker est bien demarre.
    pause
    exit /b 1
)

:: ── Démarrage et ouverture du navigateur ─────────────────────────────────────
echo.
echo  [2/2] Demarrage du configurateur...
echo.
echo  Le navigateur va s'ouvrir sur : http://localhost:5000
echo  Pour arreter : fermer cette fenetre ou Ctrl+C
echo.

:: Ouvrir le navigateur après 3 secondes
start "" /b cmd /c "timeout /t 3 >nul && start http://localhost:5000"

:: Démarrer le conteneur
docker run --rm -it ^
  -p 5000:5000 ^
  -v "%~dp0":/workspace ^
  -v "%USERPROFILE%\.ssh":/root/.ssh:ro ^
  -e TF_DATA_DIR=/root/.terraform-data/pme-infra-bootstrap ^
  --name pme-bootstrap ^
  pme-bootstrap:latest

echo.
echo  Le configurateur est arrete.
pause
