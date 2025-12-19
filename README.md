# Terraform Modules

Reusable Terraform modules for provisioning infrastructure on **Hetzner Cloud** with **Cloudflare** integration.

## Prerequisites

- Terraform >= 1.0
- Hetzner Cloud API token
- Cloudflare API token (for DNS/auth modules)
- S3 credentials (for object storage module)

## Modules

| Module                                               | Description                                         |
|------------------------------------------------------|-----------------------------------------------------|
| [hetzner/network](#hetznernetwork)                   | VPC and subnet                                      |
| [hetzner/firewall](#hetznerfirewall)                 | Ingress firewall rules                              |
| [hetzner/server-stateful](#hetznerserver-stateful)   | Database servers with delete protection and backups |
| [hetzner/server-stateless](#hetznerserver-stateless) | Web/app servers (ephemeral)                         |
| [hetzner/object-storage](#hetznerobject-storage)     | S3-compatible buckets                               |
| [cloudflare/dns](#cloudflaredns)                     | DNS records                                         |
| [cloudflare/auth](#cloudflareauth)                   | Worker-based HTTP auth and noindex headers          |

## Complete Example

Full infrastructure setup with database, web servers, DNS, and storage:

```hcl
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    minio = {
      source  = "aminueza/minio"
      version = "~> 2.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

# SSH Key
resource "hcloud_ssh_key" "default" {
  name = "deploy-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Network
module "network" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/network?ref=v1.0.0"

  name     = "production"
  ip_range = "10.0.0.0/8"
  zone     = "nbg1"
}

# Database Server (stateful)
module "database" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateful?ref=v1.0.0"

  name             = "postgres"
  type             = "cx32"
  zone             = "nbg1"
  instances_count  = 1
  network_id       = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default

  additional_firewall_rules = [
    { protocol = "tcp", port = 5432 }  # PostgreSQL
  ]
}

# Web Servers (stateless)
module "web" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateless?ref=v1.0.0"

  name             = "web"
  type             = "cx22"
  zone             = "nbg1"
  instances_count  = 2
  network_id       = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default
}

# DNS Records
module "dns" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/cloudflare/dns?ref=v1.0.0"

  token = var.cloudflare_token
  zone  = "example.com"
  name  = "production"

  records = {
    root = {
      value   = module.web.server_ips[0]
      type    = "A"
      proxied = true
    }
    www = {
      name    = "www"
      value   = module.web.server_ips[0]
      type    = "A"
      proxied = true
    }
    staging = {
      name    = "staging"
      value   = module.web.server_ips[1]
      type    = "A"
      proxied = true
    }
  }
}

# Auth Protection for Staging
module "auth" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/cloudflare/auth?ref=v1.0.0"

  token                = var.cloudflare_token
  zone                 = "example.com"
  name                 = "staging-protection"
  shared_auth_user     = var.staging_user
  shared_auth_password = var.staging_password

  protected_subdomains = [
    { name = "staging", auth = true, noindex = true }
  ]
}

# Object Storage
module "storage" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/object-storage?ref=v1.0.0"

  s3_access_key = var.s3_access_key
  s3_secret_key = var.s3_secret_key
  zone          = "nbg1"

  buckets = {
    assets = {
      name = "myapp-assets"
      acl  = "public-read"
    }
    backups = {
      name = "myapp-backups"
      acl  = "private"
    }
  }
}
```

## Module Reference

### hetzner/network

Creates a VPC with a /24 subnet.

```hcl
module "network" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/network?ref=v1.0.0"

  name     = "production"
  ip_range = "10.0.0.0/8"
  zone     = "nbg1"  # optional, default: nbg1
}
```

| Variable   | Required | Default | Description                         |
|------------|----------|---------|-------------------------------------|
| `name`     | yes      | -       | Name identifier                     |
| `ip_range` | yes      | -       | VPC CIDR block (e.g., "10.0.0.0/8") |
| `zone`     | no       | `nbg1`  | Hetzner datacenter                  |

| Output          | Description                         |
|-----------------|-------------------------------------|
| `vpc_id`        | Network ID (pass to server modules) |
| `vpc_subnet_id` | Subnet ID                           |

---

### hetzner/server-stateful

Database/stateful servers with delete protection and automatic backups enabled.

```hcl
module "database" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateful?ref=v1.0.0"

  name       = "postgres"
  type       = "cx32"
  network_id = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default

  # Optional
  zone            = "nbg1"
  instances_count = 1
  os              = "ubuntu-24.04"
  enable_backups  = true

  additional_firewall_rules = [
    { protocol = "tcp", port = 5432 }, # PostgreSQL
    { protocol = "tcp", port = 6379 }   # Redis
  ]
}
```

| Variable                    | Required | Default        | Description                          |
|-----------------------------|----------|----------------|--------------------------------------|
| `name`                      | yes      | -              | Name identifier                      |
| `type`                      | yes      | -              | Server type (cx22, cx32, cx42, etc.) |
| `network_id`                | yes      | -              | VPC ID from network module           |
| `ssh_key_resource`          | yes      | -              | hcloud_ssh_key resource              |
| `zone`                      | no       | `nbg1`         | Datacenter                           |
| `instances_count`           | no       | `1`            | Number of servers                    |
| `os`                        | no       | `ubuntu-24.04` | OS image                             |
| `enable_backups`            | no       | `true`         | Enable Hetzner backups               |
| `additional_firewall_rules` | no       | `[]`           | Extra ports to open                  |

| Output       | Description                   |
|--------------|-------------------------------|
| `server_ips` | List of public IPv4 addresses |

**Notes:**

- Delete and rebuild protection enabled
- Lifecycle `prevent_destroy` is set
- Base firewall opens port 937 (SSH)

---

### hetzner/server-stateless

Web/application servers designed for ephemeral workloads.

```hcl
module "web" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateless?ref=v1.0.0"

  name       = "web"
  type       = "cx22"
  network_id = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default

  # Optional
  zone            = "nbg1"
  instances_count = 3
  prevent_destroy = false
}
```

| Variable           | Required | Default        | Description                |
|--------------------|----------|----------------|----------------------------|
| `name`             | yes      | -              | Name identifier            |
| `type`             | yes      | -              | Server type                |
| `network_id`       | yes      | -              | VPC ID from network module |
| `ssh_key_resource` | yes      | -              | hcloud_ssh_key resource    |
| `zone`             | no       | `nbg1`         | Datacenter                 |
| `instances_count`  | no       | `1`            | Number of servers          |
| `os`               | no       | `ubuntu-24.04` | OS image                   |
| `prevent_destroy`  | no       | `false`        | Enable delete protection   |

| Output       | Description                   |
|--------------|-------------------------------|
| `server_ips` | List of public IPv4 addresses |

**Notes:**

- No automatic backups (unlike stateful)
- Base firewall opens ports 80, 443, 937

---

### hetzner/object-storage

S3-compatible object storage buckets.

```hcl
module "storage" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/object-storage?ref=v1.0.0"

  s3_access_key = var.s3_access_key
  s3_secret_key = var.s3_secret_key
  zone          = "nbg1"

  buckets = {
    public_assets = {
      name = "myapp-public"
      acl  = "public-read"
    }
    private_data = {
      name = "myapp-private"
      acl  = "private"
    }
  }
}
```

| Variable        | Required | Default | Description               |
|-----------------|----------|---------|---------------------------|
| `s3_access_key` | yes      | -       | S3 access key             |
| `s3_secret_key` | yes      | -       | S3 secret key             |
| `buckets`       | yes      | -       | Map of bucket definitions |
| `zone`          | no       | `nbg1`  | Object storage region     |

Bucket ACL options: `private`, `public-read`, `public-read-write`

| Output               | Description                  |
|----------------------|------------------------------|
| `bucket_names`       | Map of bucket names          |
| `bucket_urls`        | Map of bucket domain URLs    |
| `public_bucket_urls` | URLs for public buckets only |
| `endpoint`           | S3 endpoint URL              |

---

### cloudflare/dns

DNS record management.

```hcl
module "dns" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/cloudflare/dns?ref=v1.0.0"

  token = var.cloudflare_token
  zone  = "example.com"
  name  = "production"

  records = {
    root = {
      value   = "1.2.3.4"
      type    = "A"
      proxied = true
    }
    www = {
      name    = "www"
      value   = "1.2.3.4"
      type    = "CNAME"
      proxied = true
    }
    mail = {
      name     = "mail"
      value    = "mail.provider.com"
      type     = "MX"
      priority = 10
    }
  }
}
```

| Variable  | Required | Default | Description          |
|-----------|----------|---------|----------------------|
| `token`   | yes      | -       | Cloudflare API token |
| `zone`    | yes      | -       | Domain name          |
| `name`    | yes      | -       | Resource identifier  |
| `records` | yes      | -       | Map of DNS records   |

Record fields:

- `value` (required): Record value
- `type` (required): A, AAAA, CNAME, MX, TXT, etc.
- `name` (optional): Subdomain, default "@" (root)
- `proxied` (optional): Enable Cloudflare proxy
- `ttl` (optional): Time-to-live
- `priority` (optional): For MX/SRV records

---

### cloudflare/auth

HTTP Basic Auth and/or noindex headers via Cloudflare Workers.

```hcl
module "auth" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/cloudflare/auth?ref=v1.0.0"

  token                = var.cloudflare_token
  zone                 = "example.com"
  name                 = "staging-auth"
  shared_auth_user     = var.auth_user
  shared_auth_password = var.auth_password

  protected_subdomains = [
    { name = "staging", auth = true, noindex = true }, # Full protection
    { name = "dev", auth = true, noindex = false }, # Auth only
    { name = "preview", auth = false, noindex = true }   # Noindex only
  ]
}
```

| Variable               | Required | Default | Description                   |
|------------------------|----------|---------|-------------------------------|
| `token`                | yes      | -       | Cloudflare API token          |
| `zone`                 | yes      | -       | Domain name                   |
| `name`                 | yes      | -       | Resource identifier           |
| `shared_auth_user`     | yes      | -       | HTTP Basic Auth username      |
| `shared_auth_password` | yes      | -       | HTTP Basic Auth password      |
| `protected_subdomains` | yes      | -       | List of subdomains to protect |

Subdomain options:

- `name` (required): Subdomain name
- `auth` (optional, default: true): Enable HTTP Basic Auth
- `noindex` (optional, default: true): Add X-Robots-Tag noindex header

**Notes:**

- `.well-known` paths are excluded from auth (for ACME validation)
- Three worker scripts are deployed based on auth/noindex combinations

---

## Server Configuration

All servers are provisioned with cloud-init that:

- Creates a `kamal` user (UID 1000) with Docker and sudo access
- Configures SSH on **port 937** (not 22)
- Disables root login and password authentication
- Installs Docker, git, curl, htop, ntp
- Enables unattended security upgrades
- Disables IPv6

**SSH connection:**

```bash
ssh -p 937 kamal@<server-ip>
```

---

## Hetzner Server Types

| Type | vCPU | RAM   | Use Case              |
|------|------|-------|-----------------------|
| cx22 | 2    | 4 GB  | Small web apps        |
| cx32 | 4    | 8 GB  | Medium workloads      |
| cx42 | 8    | 16 GB | Databases, heavy apps |
| cx52 | 16   | 32 GB | Large databases       |

## Zones

| Zone | Location             |
|------|----------------------|
| nbg1 | Nuremberg, Germany   |
| fsn1 | Falkenstein, Germany |
| hel1 | Helsinki, Finland    |

---

## Version Pinning

Always pin to a specific version:

```hcl
source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/network?ref=v1.0.0"
```
