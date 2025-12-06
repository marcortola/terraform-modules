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

variable "shared_auth_user" {
  description = "Basic HTTP Username"
  type        = string
  sensitive   = true
}

variable "shared_auth_password" {
  description = "Basic HTTP Username"
  type        = string
  sensitive   = true
}

variable "protected_subdomains" {
  description = "An array of subdomains to protect"
  type = list(object({
    name    = string
    auth    = optional(bool, true)
    noindex = optional(bool, true)
  }))
}