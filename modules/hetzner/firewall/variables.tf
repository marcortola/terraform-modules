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
    # cidrhost(ip, 0) prints the network address in canonical form, so this rejects
    # host bits ("10.0.0.5/24") and non-canonical IPv6 ("2001:DB8::/32").
    condition     = alltrue(flatten([for r in var.rule : [for ip in r.source_ips : try(cidrhost(ip, 0) == split("/", ip)[0], false)]]))
    error_message = "Each source_ips entry must be a network CIDR block in canonical form, such as \"203.0.113.10/32\" or \"2001:db8::/32\": no host bits set (\"10.0.0.0/24\", not \"10.0.0.5/24\"), and IPv6 in lower case with zeros compressed."
  }
}

variable "apply_to" {
  description = "Servers to attach the firewall to. Each entry sets exactly one of server (a server ID) or label_selector."
  type = list(object({
    server         = optional(number)
    label_selector = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for a in var.apply_to : (a.server == null) != (a.label_selector == null)])
    error_message = "Each apply_to entry must set exactly one of server or label_selector."
  }
}
