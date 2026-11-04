terraform {
  # Optional object attributes with defaults need Terraform 1.3.
  required_version = ">= 1.3"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}