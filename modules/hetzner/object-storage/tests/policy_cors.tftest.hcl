# Plan-only tests for per-bucket policy and CORS rules. Needs Terraform 1.7+ for mock_provider.

mock_provider "minio" {}

variables {
  s3_access_key = "test-access-key"
  s3_secret_key = "test-secret-key"
}

run "v1_9_0_inputs_plan_buckets_only" {
  command = plan

  variables {
    buckets = {
      assets = { name = "myapp-public", acl = "public-read" }
      data   = { name = "myapp-private" }
    }
  }

  assert {
    condition     = keys(minio_s3_bucket.buckets) == ["assets", "data"]
    error_message = "Expected one bucket per entry, keyed by the map keys as in v1.9.0."
  }

  assert {
    condition     = minio_s3_bucket.buckets["assets"].acl == "public-read" && minio_s3_bucket.buckets["data"].acl == "private"
    error_message = "Each bucket must keep its acl, with private as the default."
  }

  assert {
    condition     = length(minio_s3_bucket_policy.buckets) == 0
    error_message = "Buckets without a policy must plan no bucket policy."
  }

  assert {
    condition     = length(minio_s3_bucket_cors.buckets) == 0
    error_message = "Buckets without cors_rules must plan no CORS configuration."
  }

  assert {
    condition     = keys(output.public_bucket_urls) == ["assets"]
    error_message = "public_bucket_urls must list only the public-read bucket."
  }
}

run "policy_and_cors_plan_one_of_each" {
  command = plan

  variables {
    buckets = {
      screenshots = {
        name = "app-screenshots"
        acl  = "private"
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect    = "Allow"
            Principal = { AWS = ["*"] }
            Action    = ["s3:GetObject"]
            Resource  = ["arn:aws:s3:::app-screenshots/*"]
          }]
        })
        cors_rules = [{
          allowed_origins = ["https://app.example.com", "http://localhost:3000"]
          allowed_methods = ["PUT"]
          allowed_headers = ["content-type"]
          max_age_seconds = 3600
        }]
      }
      data = { name = "myapp-private" }
    }
  }

  assert {
    condition     = keys(minio_s3_bucket_policy.buckets) == ["screenshots"]
    error_message = "Expected one bucket policy, for the bucket that sets one."
  }

  assert {
    condition     = minio_s3_bucket_policy.buckets["screenshots"].bucket == "app-screenshots"
    error_message = "The policy must target the bucket's name."
  }

  assert {
    condition     = jsondecode(minio_s3_bucket_policy.buckets["screenshots"].policy).Statement[0].Action == ["s3:GetObject"]
    error_message = "The policy must be passed through unchanged."
  }

  assert {
    condition     = keys(minio_s3_bucket_cors.buckets) == ["screenshots"]
    error_message = "Expected one CORS configuration, for the bucket that sets rules."
  }

  assert {
    condition     = minio_s3_bucket_cors.buckets["screenshots"].bucket == "app-screenshots"
    error_message = "The CORS configuration must target the bucket's name."
  }

  assert {
    condition     = length(minio_s3_bucket_cors.buckets["screenshots"].cors_rule) == 1
    error_message = "Expected one cors_rule block per input rule."
  }

  assert {
    condition = (
      minio_s3_bucket_cors.buckets["screenshots"].cors_rule[0].allowed_origins == tolist(["https://app.example.com", "http://localhost:3000"])
      && minio_s3_bucket_cors.buckets["screenshots"].cors_rule[0].allowed_methods == tolist(["PUT"])
      && minio_s3_bucket_cors.buckets["screenshots"].cors_rule[0].allowed_headers == tolist(["content-type"])
      && minio_s3_bucket_cors.buckets["screenshots"].cors_rule[0].max_age_seconds == 3600
    )
    error_message = "The cors_rule must carry the input rule's origins, methods, headers and max age."
  }

  assert {
    condition     = output.public_bucket_urls == {}
    error_message = "A bucket public through its policy is absent from public_bucket_urls, which filters on acl."
  }
}

run "policy_and_cors_are_independent" {
  command = plan

  variables {
    buckets = {
      policy_only = {
        name   = "policy-only"
        policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
      cors_only = {
        name = "cors-only"
        cors_rules = [
          { allowed_origins = ["https://a.example.com"], allowed_methods = ["GET", "HEAD"] },
          { allowed_origins = ["https://b.example.com"], allowed_methods = ["PUT", "POST", "DELETE"], expose_headers = ["ETag"] },
        ]
      }
    }
  }

  assert {
    condition     = keys(minio_s3_bucket_policy.buckets) == ["policy_only"]
    error_message = "Only the bucket with a policy must plan a bucket policy."
  }

  assert {
    condition     = keys(minio_s3_bucket_cors.buckets) == ["cors_only"]
    error_message = "Only the bucket with cors_rules must plan a CORS configuration."
  }

  assert {
    condition     = length(minio_s3_bucket_cors.buckets["cors_only"].cors_rule) == 2
    error_message = "Expected one cors_rule block per input rule."
  }

  assert {
    condition     = minio_s3_bucket_cors.buckets["cors_only"].cors_rule[1].expose_headers == tolist(["ETag"])
    error_message = "Each cors_rule must keep its own expose_headers."
  }
}

run "empty_cors_rules_plan_no_cors" {
  command = plan

  variables {
    buckets = {
      data = { name = "myapp-private", cors_rules = [] }
    }
  }

  assert {
    condition     = length(minio_s3_bucket_cors.buckets) == 0
    error_message = "An empty cors_rules list must plan no CORS configuration."
  }
}

run "rejects_non_json_policy" {
  command = plan

  variables {
    buckets = {
      data = { name = "myapp-private", policy = "not json" }
    }
  }

  expect_failures = [var.buckets]
}

run "rejects_json_policy_that_is_not_an_object" {
  command = plan

  variables {
    buckets = {
      data = { name = "myapp-private", policy = "[]" }
    }
  }

  expect_failures = [var.buckets]
}

run "rejects_unknown_cors_method" {
  command = plan

  variables {
    buckets = {
      data = {
        name       = "myapp-private"
        cors_rules = [{ allowed_origins = ["https://app.example.com"], allowed_methods = ["PUT", "PATCH"] }]
      }
    }
  }

  expect_failures = [var.buckets]
}

run "rejects_lower_case_cors_method" {
  command = plan

  variables {
    buckets = {
      data = {
        name       = "myapp-private"
        cors_rules = [{ allowed_origins = ["https://app.example.com"], allowed_methods = ["put"] }]
      }
    }
  }

  expect_failures = [var.buckets]
}

run "rejects_policy_with_public_read_acl" {
  command = plan

  variables {
    buckets = {
      assets = {
        name   = "myapp-public"
        acl    = "public-read"
        policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  expect_failures = [var.buckets]
}

run "rejects_policy_with_public_read_write_acl" {
  command = plan

  variables {
    buckets = {
      assets = {
        name   = "myapp-public"
        acl    = "public-read-write"
        policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  expect_failures = [var.buckets]
}
