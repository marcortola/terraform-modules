variable "token" {
  description = "CloudflareAPI Token"
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "zone" {
  description = "domain.com"
  type        = string
}

variable "records" {
  description = "A map of DNS records to be created"
  type = map(object({
    name = optional(string, "@")
    value = string
    type  = string
    ttl = optional(number)
    proxied = optional(bool)
    priority = optional(number)
  }))
}