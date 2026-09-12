# =============================================================================
# 02-install-cloudbase-init.ps1
# Installe et configure cloudbase-init pour Proxmox (datasource NoCloud / ConfigDrive).
# Cloudbase-init remplace cloud-init sur Windows : il lit les métadonnées Proxmox
# au 1er boot et applique le nom de machine, le mot de passe, les clés SSH, etc.
# =============================================================================
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$installerUrl  = "https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi"
$installerPath = "$env:TEMP\cloudbase-init.msi"

Write-Host "==> Téléchargement de cloudbase-init..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

Write-Host "==> Installation de cloudbase-init..."
$proc = Start-Process msiexec.exe `
    -ArgumentList "/i `"$installerPath`" /qn /norestart LOGGINGLEVEL=DEBUG" `
    -Wait -PassThru
if ($proc.ExitCode -notin @(0, 3010)) {
    Write-Error "L'installation de cloudbase-init a échoué (code $($proc.ExitCode))"
    exit $proc.ExitCode
}
Write-Host "    → cloudbase-init installé."

# ---------------------------------------------------------------------------
# Configuration cloudbase-init pour Proxmox
# Proxmox expose les données cloud-init via un drive "NoCloud" (config drive v2)
# monté comme un disque VFAT/ISO9660 (ide2 dans Terraform).
# ---------------------------------------------------------------------------
$confDir  = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf"
$confFile = "$confDir\cloudbase-init.conf"

Write-Host "==> Écriture de la configuration cloudbase-init..."
Set-Content -Path $confFile -Encoding UTF8 -Value @"
[DEFAULT]
username=Administrator
groups=Administrators
inject_user_password=true
first_logon_behaviour=no

# Proxmox monte le drive cloud-init en tant que lecteur VFAT ou ISO (config drive v2)
config_drive_types=vfat,iso
config_drive_locations=hdd
datasources_enabled=ConfigDriveV2
datasources=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService

# Plugins actifs
plugins=cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,
        cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,
        cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,
        cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,
        cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,
        cloudbaseinit.plugins.windows.winrmlistener.ConfigWinRMListenerPlugin,
        cloudbaseinit.plugins.windows.winrmcertificateauth.ConfigWinRMCertificateAuthPlugin

# Serial console pour les logs (visible dans la console Proxmox)
logging_serial_port_settings=COM1,9600,N,8
mtu_use_dhcp_config=true
debug=true
"@

# ---------------------------------------------------------------------------
# Configuration cloudbase-init-unattend.conf (exécuté avant sysprep)
# ---------------------------------------------------------------------------
$unattendFile = "$confDir\cloudbase-init-unattend.conf"
Set-Content -Path $unattendFile -Encoding UTF8 -Value @"
[DEFAULT]
username=Administrator
groups=Administrators
inject_user_password=true
first_logon_behaviour=no
config_drive_types=vfat,iso
config_drive_locations=hdd
datasources_enabled=ConfigDriveV2
datasources=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
plugins=cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,
        cloudbaseinit.plugins.windows.createuser.CreateUserPlugin
"@

Write-Host "    → Configuration écrite dans $confFile"
Write-Host "==> cloudbase-init configuré pour Proxmox (ConfigDriveV2 / VFAT)."
