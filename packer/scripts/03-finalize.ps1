# =============================================================================
# 03-finalize.ps1
# Dernière étape Packer :
#   1. Configure WinRM de façon permanente pour Ansible (HTTPS + Basic auth)
#   2. Active les règles de pare-feu pour WinRM et RDP
#   3. Nettoie les fichiers temporaires
#   4. Lance le sysprep — Windows s'arrête, Packer crée le template Proxmox
# =============================================================================
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 1. WinRM pour Ansible (production)
# On configure HTTPS (port 5986) avec un certificat auto-signé.
# ansible_connection = winrm, ansible_winrm_transport = ntlm ou basic
# ---------------------------------------------------------------------------
Write-Host "==> Configuration WinRM permanente pour Ansible..."

# Créer un certificat auto-signé valable 10 ans
$cert = New-SelfSignedCertificate `
    -DnsName "$(hostname)" `
    -CertStoreLocation "cert:\LocalMachine\My" `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(10)

# Créer le listener HTTPS
$null = New-Item -Path "WSMan:\localhost\Listener" `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force

# Autoriser auth basique et non-chiffrée (HTTP reste possible en local)
Set-Item WSMan:\localhost\Service\Auth\Basic   -Value $true
Set-Item WSMan:\localhost\Service\Auth\CredSSP -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Augmenter la mémoire max par shell (Ansible peut envoyer de gros payloads)
Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024

Write-Host "    → WinRM HTTPS configuré (certificat thumbprint : $($cert.Thumbprint))"

# ---------------------------------------------------------------------------
# 2. Règles pare-feu
# ---------------------------------------------------------------------------
Write-Host "==> Règles de pare-feu..."

$firewallRules = @(
    @{ Name = "WinRM HTTP";  Port = 5985 },
    @{ Name = "WinRM HTTPS"; Port = 5986 },
    @{ Name = "RDP";          Port = 3389 }
)
foreach ($rule in $firewallRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule `
            -DisplayName $rule.Name `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $rule.Port `
            -Action Allow | Out-Null
        Write-Host "    → Règle créée : $($rule.Name) (port $($rule.Port))"
    } else {
        Write-Host "    → Règle existante : $($rule.Name)"
    }
}

# ---------------------------------------------------------------------------
# 3. Désactiver Windows Update pendant le template (cloudbase-init le réactivera si besoin)
# ---------------------------------------------------------------------------
Write-Host "==> Désactivation de Windows Update automatique (template)..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
    -Name "NoAutoUpdate" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# 4. Nettoyage
# ---------------------------------------------------------------------------
Write-Host "==> Nettoyage..."
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Vider le journal des événements Windows
wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }

Write-Host "==> Nettoyage terminé."

# ---------------------------------------------------------------------------
# 5. Sysprep
# Lance le generalize + OOBE + shutdown.
# Packer détecte l'arrêt de la VM et la convertit en template Proxmox.
# cloudbase-init se lancera au 1er boot de chaque VM clonée.
# ---------------------------------------------------------------------------
Write-Host "==> Lancement du sysprep (la VM va s'arrêter — template en cours de création)..."

$sysprepArgs = "/oobe /generalize /quiet /shutdown /unattend:""C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"""

# Utiliser l'Unattend.xml de cloudbase-init s'il existe, sinon sysprep simple
$cloudbaseUnattend = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"
if (Test-Path $cloudbaseUnattend) {
    Write-Host "    → Sysprep avec Unattend cloudbase-init"
    & "C:\Windows\System32\Sysprep\sysprep.exe" /oobe /generalize /quiet /shutdown /unattend:"$cloudbaseUnattend"
} else {
    Write-Host "    → Sysprep sans Unattend (cloudbase-init Unattend.xml introuvable)"
    & "C:\Windows\System32\Sysprep\sysprep.exe" /oobe /generalize /quiet /shutdown
}
