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
  description = "Map of S3 buckets to create, each with an optional bucket policy and CORS rules"
  type = map(object({
    name   = string
    acl    = optional(string, "private")
    policy = optional(string)
    cors_rules = optional(list(object({
      allowed_origins = list(string)
      allowed_methods = list(string)
      allowed_headers = optional(list(string))
      expose_headers  = optional(list(string))
      max_age_seconds = optional(number)
    })), [])
  }))

  validation {
    condition = alltrue([
      for bucket in var.buckets : contains(["private", "public-read", "public-read-write"], bucket.acl)
    ])
    error_message = "Bucket ACL must be one of: private, public-read, public-read-write."
  }

  # The minio provider's acl is not an S3 ACL but a bucket-policy writer: public-read writes
  # the canned "download" policy, which also grants s3:ListBucket, and private removes the
  # policy. acl and policy would overwrite each other, so a custom policy needs acl = "private".
  validation {
    condition = alltrue([
      for bucket in var.buckets : bucket.policy == null || bucket.acl == "private"
    ])
    error_message = "A bucket with a policy must use acl = \"private\": the provider's acl writes the bucket policy too."
  }

  validation {
    condition = alltrue([
      for bucket in var.buckets : bucket.policy == null || can(keys(jsondecode(bucket.policy)))
    ])
    error_message = "A bucket policy must be a JSON object, such as the output of jsonencode()."
  }

  validation {
    condition = alltrue(flatten([
      for bucket in var.buckets : [
        for rule in bucket.cors_rules : [
          for method in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], method)
        ]
      ]
    ]))
    error_message = "CORS allowed_methods must be among: GET, PUT, POST, DELETE, HEAD (upper case)."
  }
}
