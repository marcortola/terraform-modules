provider "minio" {
  minio_server   = "${var.zone}.your-objectstorage.com"
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_region   = var.zone
  minio_ssl      = true
}

resource "minio_s3_bucket" "buckets" {
  for_each = var.buckets
  bucket        = each.value.name
  acl           = each.value.acl
}