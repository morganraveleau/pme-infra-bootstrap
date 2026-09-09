provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = true # à passer à false une fois un certificat valide en place sur Proxmox
}

# --- VM 1 : k3s-node1 (Debian 12, control-plane + worker) ---------------
module "k3s_node1" {
  source = "./modules/proxmox-vm"

  name        = "${var.company_name}-k3s-node1"
  node_name   = var.pm_node
  template_id = var.k3s_vm.template_id
  vcpu        = var.k3s_vm.vcpu
  memory_mb   = var.k3s_vm.memory_mb
  disk_gb     = var.k3s_vm.disk_gb
  ip_address  = var.k3s_vm.ip_address
  gateway     = var.k3s_vm.gateway
  bridge      = var.network_bridge
  tags        = ["bootstrap-pme", "k3s"]
}

# --- VM 2 : ad-dc1 (Windows Server, contrôleur de domaine) --------------
module "ad_dc1" {
  source = "./modules/proxmox-vm"

  name        = "${var.company_name}-ad-dc1"
  node_name   = var.pm_node
  template_id = var.ad_vm.template_id
  vcpu        = var.ad_vm.vcpu
  memory_mb   = var.ad_vm.memory_mb
  disk_gb     = var.ad_vm.disk_gb
  ip_address  = var.ad_vm.ip_address
  gateway     = var.ad_vm.gateway
  bridge      = var.network_bridge
  tags        = ["bootstrap-pme", "active-directory"]
}
