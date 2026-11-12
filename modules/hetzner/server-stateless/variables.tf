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
    protocol   = string
    port       = number
    source_ips = optional(list(string))
  }))
  default     = []
  description = "Additional inbound firewall rules with protocol, port and optional source_ips (CIDR blocks; omitted means all IPv4 and IPv6 addresses)"
}

variable "web_source_ips" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  nullable    = false
  description = "Source CIDR blocks allowed to reach the base HTTP (80) and HTTPS (443) rules. Port 937 (SSH) stays open to all addresses. Ignored when web_ports_enabled is false."
}

variable "web_ports_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether the base firewall opens HTTP (80) and HTTPS (443) to web_source_ips. False omits both base rules and leaves port 937 (SSH, open to all addresses) plus additional_firewall_rules, for servers that serve no web traffic such as workers."
}

variable "keep_disk_size_to_allow_downgrades" {
  description = "Whether to keep the server disk when deleting the server to allow downgrades"
  type        = bool
  default     = true
}

variable "network_ips" {
  type        = list(string)
  description = "Static private IP addresses for each server instance. Length must match instances_count, or leave empty for auto-assignment."
  default     = []
}

variable "prevent_destroy" {
  description = "Whether to prevent the server from being destroyed"
  type        = bool
  default     = false
}

variable "additional_cloudinit_parts" {
  description = "Extra cloud-init parts appended to the server's user_data (e.g. an nftables egress ACL). Rendered after the base parts; each merges onto the accumulated config with list-append semantics by default. Applies only on fresh hosts (user_data is in ignore_changes)."
  type = list(object({
    content_type = optional(string, "text/cloud-config")
    content      = string
    merge_type   = optional(string, "list(append)+dict(recurse_array)+str()")
  }))
  default = []
}

variable "audit_ssh_public_key" {
  description = "Optional SSH public key for an `audit` account created by cloud-init: password locked, shell /bin/sh, no supplementary groups or sudo, and the key restricted to the forced command /usr/local/bin/infra-audit-dispatch, which the consumer installs. When set, sshd also allows `audit` (AllowUsers kamal audit). One line starting with `ssh-` and no trailing newline (wrap file() in trimspace()). Applies only on fresh hosts (user_data is in ignore_changes). Null renders the same cloud-init as before."
  type        = string
  default     = null

  validation {
    condition     = var.audit_ssh_public_key == null || can(regex("^ssh-[^[:cntrl:]]*$", var.audit_ssh_public_key))
    error_message = "audit_ssh_public_key must be null or a single line starting with \"ssh-\" (no newline)."
  }
}
