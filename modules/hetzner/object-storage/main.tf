provider "minio" {
  minio_server   = "${var.zone}.your-objectstorage.com"
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_region   = var.zone
  minio_ssl      = true

  # The provider is built for MinIO; its docs require this flag on every other S3 backend,
  # Hetzner included: reading a sub-resource Hetzner does not implement keeps the last written
  # state and logs a warning (visible with TF_LOG) instead of failing the plan.
  s3_compat_mode = true
}

resource "minio_s3_bucket" "buckets" {
  for_each = var.buckets
  bucket   = each.value.name
  acl      = each.value.acl

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [bucket_prefix]
  }
}

# bucket references the bucket resource rather than var.buckets, so the policy is written
# after the bucket's create, whose acl = "private" removes any bucket policy.
resource "minio_s3_bucket_policy" "buckets" {
  for_each = { for k, v in var.buckets : k => v if v.policy != null }
  bucket   = minio_s3_bucket.buckets[each.key].bucket
  policy   = each.value.policy
}

resource "minio_s3_bucket_cors" "buckets" {
  for_each = { for k, v in var.buckets : k => v if length(v.cors_rules) > 0 }
  bucket   = minio_s3_bucket.buckets[each.key].bucket

  dynamic "cors_rule" {
    for_each = each.value.cors_rules

    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}
