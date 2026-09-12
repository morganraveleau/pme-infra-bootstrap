variable "name"           { type = string }
variable "node_name"      { type = string }
variable "template_id"    { type = number }
variable "vcpu"           { type = number; default = 2 }
variable "memory_mb"      { type = number; default = 4096 }
variable "disk_gb"        { type = number; default = 40 }
variable "ip_address"     { type = string }
variable "gateway"        { type = string }
variable "bridge"         { type = string; default = "vmbr0" }
variable "datastore"      { type = string; default = "local-lvm" }
variable "ssh_public_key" { type = string; default = "" }
variable "tags"           { type = list(string); default = [] }
variable "is_windows" {
  description = "Si true, ne pas injecter user_account cloud-init (cloudbase-init gère le Windows)"
  type        = bool
  default     = false
}
