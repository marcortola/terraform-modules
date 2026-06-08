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
  description = "Source domain whose traffic should be redirected (e.g. old-domain.com)"
  type        = string
}

variable "rules" {
  description = "A map of per-host redirect rules. Each entry produces one rule in a single Cloudflare Dynamic Redirect ruleset on the zone."
  type = map(object({
    source_host     = string
    target_url      = string
    preserve_path   = optional(bool, true)
    preserve_query  = optional(bool, true)
    status_code     = optional(number, 301)
    placeholder_dns = optional(bool, false)
  }))
  default = {}
}
