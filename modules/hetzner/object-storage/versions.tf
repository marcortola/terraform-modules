terraform {
  required_providers {
    minio = {
      source = "aminueza/minio"
      # 3.44.0 made s3_compat_mode (main.tf) cover bucket policies and match only real
      # unsupported answers; earlier releases apply it to CORS alone, by loose error text.
      version = "~> 3.44"
    }
  }
}
