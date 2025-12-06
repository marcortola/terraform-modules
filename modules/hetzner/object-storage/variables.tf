variable "s3_access_key" {
  description = "S3 access key for Hetzner Object Storage"
  type        = string
  sensitive   = true
}

variable "s3_secret_key" {
  description = "S3 secret key for Hetzner Object Storage"
  type        = string
  sensitive   = true
}

variable "zone" {
  type        = string
  description = "Server location, use 'hcloud location list' to get a list of valid choices"
  default     = "nbg1"
}

variable "buckets" {
  description = "Map of S3 buckets to create"
  type = map(object({
    name                    = string
    acl                     = optional(string, "private")
  }))

  validation {
    condition = alltrue([
      for bucket in var.buckets : contains(["private", "public-read", "public-read-write"], bucket.acl)
    ])
    error_message = "Bucket ACL must be one of: private, public-read, public-read-write."
  }
}