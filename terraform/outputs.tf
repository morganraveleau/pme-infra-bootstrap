output "k3s_node1_ip" {
  description = "Adresse IP de la VM k3s-node1 (sans masque)"
  value       = split("/", var.k3s_vm.ip_address)[0]
}

output "ad_dc1_ip" {
  description = "Adresse IP de la VM ad-dc1 (sans masque)"
  value       = split("/", var.ad_vm.ip_address)[0]
}

output "debian12_template_id" {
  description = "ID du template Debian 12 cloud-init créé automatiquement (9000)"
  value       = proxmox_virtual_environment_vm.debian12_template.vm_id
}

# TODO : une fois l'inventaire Ansible dynamique en place, générer
# ansible/inventory/hosts.yml directement depuis ces outputs (local_file + templatefile).
