variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "ssh_key_resource" {
  description = "Hetzner Cloud SSH key resource"
  type        = any
  sensitive   = true
}

variable "zone" {
  type        = string
  description = "Server location, use 'hcloud location list' to get a list of valid choices"
  default     = "nbg1"
}

variable "instances_count" {
  type    = number
  default = 1
}

variable "type" {
  type        = string
  description = "Server type of created server, use 'hcloud server-type list' to get a list of valid choices"
}

variable "os" {
  type        = string
  description = "OS image used for server, use 'hcloud image list' to get a list of valid choices"
  default     = "ubuntu-24.04"
}

variable "network_id" {
  type        = string
  description = "ID of the network the server should be attached to"
}

variable "additional_firewall_rules" {
  type = list(object({
    protocol = string
    port     = number
  }))
  default = []
  description = "Additional firewall rules with protocol and port"
}

variable "keep_disk_size_to_allow_downgrades" {
  description = "Whether to keep the server disk when deleting the server to allow downgrades"
  type        = bool
  default     = true
}

variable "prevent_destroy" {
  description = "Whether to prevent the server from being destroyed"
  type        = bool
  default     = false
}