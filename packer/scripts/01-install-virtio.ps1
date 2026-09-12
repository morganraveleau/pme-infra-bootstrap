# =============================================================================
# 01-install-virtio.ps1
# Installe tous les drivers VirtIO depuis le CD monté en ide1 (D: ou E:).
# Drivers installés : stockage (viostor/vioscsi), réseau (netkvm),
# ballon mémoire, entrée tablet, serial, QEMU guest agent.
# =============================================================================
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "==> Recherche du lecteur VirtIO ISO..."

# L'ISO VirtIO peut être sur D: ou E: selon la configuration Proxmox.
# On cherche la présence de 'viostor' pour identifier le bon lecteur.
$virtioLetter = $null
foreach ($letter in @('D','E','F')) {
    if (Test-Path "${letter}:\viostor") {
        $virtioLetter = $letter
        break
    }
}

if (-not $virtioLetter) {
    Write-Error "VirtIO ISO introuvable sur D:, E: ou F:. Vérifie que ide1 est bien monté."
    exit 1
}

Write-Host "==> VirtIO trouvé sur ${virtioLetter}:"

# Dossiers de drivers pour Windows Server 2022 (w11 = alias 2k22 dans l'ISO Fedora)
$driverPaths = @(
    "${virtioLetter}:\viostor\2k22\amd64",      # SCSI storage
    "${virtioLetter}:\vioscsi\2k22\amd64",      # SCSI passthrough
    "${virtioLetter}:\netkvm\2k22\amd64",       # Réseau VirtIO
    "${virtioLetter}:\balloon\2k22\amd64",      # Memory balloon
    "${virtioLetter}:\vioserial\2k22\amd64",    # Port série virtuel
    "${virtioLetter}:\vioser\2k22\amd64",       # Alias vioserial (variante ISO)
    "${virtioLetter}:\vioinput\2k22\amd64",     # Tablet / souris VirtIO
    "${virtioLetter}:\pvpanic\2k22\amd64",      # Panic device
    "${virtioLetter}:\qxldod\2k22\amd64"        # GPU QXL
)

$installed = 0
$skipped   = 0

foreach ($path in $driverPaths) {
    if (-not (Test-Path $path)) {
        Write-Host "  [skip] $path (introuvable)"
        $skipped++
        continue
    }
    $infFiles = Get-ChildItem -Path $path -Filter "*.inf" -ErrorAction SilentlyContinue
    foreach ($inf in $infFiles) {
        Write-Host "  [install] $($inf.FullName)"
        $result = & pnputil /add-driver $inf.FullName /install 2>&1
        Write-Host "    → $result"
        $installed++
    }
}

Write-Host "==> VirtIO : $installed driver(s) installé(s), $skipped chemin(s) ignoré(s)."

# ---------------------------------------------------------------------------
# QEMU Guest Agent (qemu-ga)
# Installé depuis l'ISO VirtIO, pas depuis les drivers PnP.
# ---------------------------------------------------------------------------
Write-Host "==> Installation du QEMU Guest Agent..."

$qemuGaPath = "${virtioLetter}:\guest-agent\qemu-ga-x86_64.msi"
if (Test-Path $qemuGaPath) {
    Start-Process msiexec.exe -ArgumentList "/i `"$qemuGaPath`" /qn /norestart" -Wait
    Write-Host "    → qemu-ga installé."
} else {
    Write-Warning "    QEMU Guest Agent MSI introuvable à $qemuGaPath — ignoré."
}
