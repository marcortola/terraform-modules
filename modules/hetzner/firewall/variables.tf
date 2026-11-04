variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "rule" {
  description = "Inbound firewall rules. Each rule accepts traffic from source_ips, which defaults to all IPv4 and IPv6 addresses."
  type = list(object({
    protocol   = string
    port       = number
    source_ips = optional(list(string), ["0.0.0.0/0", "::/0"])
  }))

  validation {
    condition     = alltrue([for r in var.rule : length(r.source_ips) > 0])
    error_message = "Each rule needs at least one entry in source_ips."
  }

  validation {
    condition     = alltrue(flatten([for r in var.rule : [for ip in r.source_ips : can(cidrhost(ip, 0))]]))
    error_message = "Each source_ips entry must be a CIDR block, such as \"203.0.113.10/32\" or \"2001:db8::/32\"."
  }
}

variable "apply_to" {
  type = list(object({
    label_selector = string
  }))
  default = []
}
