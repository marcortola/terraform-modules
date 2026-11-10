output "bucket_names" {
  description = "Names of the created buckets"
  value       = { for k, v in minio_s3_bucket.buckets : k => v.bucket }
}

output "bucket_ids" {
  description = "IDs of the created buckets"
  value       = { for k, v in minio_s3_bucket.buckets : k => v.id }
}

output "bucket_arns" {
  description = "ARNs of the created buckets"
  value       = { for k, v in minio_s3_bucket.buckets : k => v.arn }
}

output "bucket_urls" {
  description = "URLs of the created buckets"
  value       = { for k, v in minio_s3_bucket.buckets : k => v.bucket_domain_name }
}

output "endpoint" {
  description = "Hetzner Object Storage endpoint"
  value       = "${var.zone}.your-objectstorage.com"
}

output "zone" {
  description = "Hetzner Object Storage location"
  value       = var.zone
}

output "public_bucket_urls" {
  description = "Public URLs for buckets with public-read or public-read-write ACL. A bucket made public by its policy (acl private) is not included, since this filters on acl."
  value = {
    for k, v in minio_s3_bucket.buckets : k => "https://${v.bucket}.${var.zone}.your-objectstorage.com"
    if var.buckets[k].acl == "public-read" || var.buckets[k].acl == "public-read-write"
  }
}