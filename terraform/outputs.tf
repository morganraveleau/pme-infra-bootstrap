output "k3s_node1_ip" {
  description = "Adresse IP de la VM k3s-node1 (sans le masque)"
  value       = split("/", var.k3s_vm.ip_address)[0]
}

output "ad_dc1_ip" {
  description = "Adresse IP de la VM ad-dc1"
  value       = split("/", var.ad_vm.ip_address)[0]
}

# TODO (J5, J10) : une fois l'inventaire Ansible dynamique en place,
# envisager de générer ansible/inventory/hosts.yml directement depuis ces outputs
# (local_file + template) pour éviter la duplication IP entre Terraform et Ansible.
