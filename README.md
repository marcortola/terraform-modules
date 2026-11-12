# Terraform Modules

Reusable Terraform modules for provisioning infrastructure on **Hetzner Cloud** with **Cloudflare** integration.

## Prerequisites

- Terraform 1.3 or later; the supported optional Nix devShell pins it (`direnv allow` or
  `nix develop`), but a compatible native installation also works. The module tests
  (`terraform test` in a module that has a `tests/` directory) need Terraform 1.7 or later.
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
| [cloudflare/redirect](#cloudflareredirect)           | Per-host 301/302 redirects via Single Redirects     |

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
      version = "~> 3.44"
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

### hetzner/firewall

Inbound firewall. The server modules call it for their base and additional rules and
attach it to their servers.

```hcl
module "firewall" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/firewall?ref=v1.9.0"

  name = "web"

  rule = [
    { protocol = "tcp", port = 443, source_ips = ["173.245.48.0/20", "2400:cb00::/32"] },
    { protocol = "tcp", port = 937 }, # open to all
  ]

  # Optional: attach the firewall here. The server modules attach it through
  # hcloud_server.firewall_ids instead and pass no apply_to.
  apply_to = [
    { server = hcloud_server.web.id },
    { label_selector = "role=web" },
  ]
}
```

| Variable   | Required | Default | Description                               |
|------------|----------|---------|-------------------------------------------|
| `name`     | yes      | -       | Name identifier                           |
| `rule`     | yes      | -       | Inbound rules (see below)                 |
| `apply_to` | no       | `[]`    | Servers to attach the firewall to (below) |

Rule fields:

- `protocol` (required): `tcp` or `udp`
- `port` (required): port number
- `source_ips` (optional, default `["0.0.0.0/0", "::/0"]`): CIDR blocks allowed to
  connect; it must not be empty, and a single address needs a prefix such as `/32`.
  Each entry must be a network address in canonical form: no host bits set
  (`10.0.0.0/24`, not `10.0.0.5/24`) and IPv6 in lower case with zeros compressed
  (`2001:db8::/32`, not `2001:DB8:0::/32`), the form Terraform's `cidrhost` prints.
  Hetzner Cloud firewalls filter only public interfaces, so list public addresses.
  Requires v1.9.0 or later; older versions silently ignore `source_ips` and open the
  port to all addresses.

`apply_to` entries take exactly one of:

- `server`: a server ID
- `label_selector`: a label selector, such as `role=web`

| Output       | Description                                    |
|--------------|------------------------------------------------|
| `ingress_id` | Firewall ID (pass to `hcloud_server`)          |
| `rules`      | Rendered inbound rules, including `source_ips` |

---

### hetzner/server-stateful

Database/stateful servers with delete protection and automatic backups enabled.

```hcl
module "database" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateful?ref=v1.9.0"

  name       = "postgres"
  type       = "cx32"
  network_id = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default

  # Optional
  zone            = "nbg1"
  instances_count = 1
  os              = "ubuntu-24.04"
  enable_backups  = true

  # Optional audit account for new servers (requires v1.11.0 or later).
  audit_ssh_public_key = trimspace(file("~/.ssh/audit.pub"))

  # source_ips requires v1.9.0 or later; older versions silently ignore it and
  # open the port to all addresses.
  additional_firewall_rules = [
    { protocol = "tcp", port = 5432, source_ips = ["203.0.113.10/32"] }, # PostgreSQL, admin IP only
    { protocol = "tcp", port = 6379 }                                    # Redis, open to all
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
| `additional_firewall_rules` | no       | `[]`           | Extra rules to open (see below)      |
| `audit_ssh_public_key`      | no       | `null`         | Audit account key (see below)        |

| Output       | Description                   |
|--------------|-------------------------------|
| `server_ips` | List of public IPv4 addresses |

**Notes:**

- Delete and rebuild protection enabled
- Lifecycle `prevent_destroy` is set
- Base firewall opens port 937 (SSH) to all addresses
- Each `additional_firewall_rules` entry takes `protocol`, `port` and an optional
  `source_ips` list of CIDR blocks (see [hetzner/firewall](#hetznerfirewall)); without
  `source_ips` the rule accepts `0.0.0.0/0` and `::/0`. `source_ips` requires v1.9.0
  or later: older versions silently ignore it and open the port to all addresses.
- `audit_ssh_public_key` adds a locked `audit` account to cloud-init (see
  [Audit account](#audit-account)); it only affects newly created servers, since
  `user_data` is in `ignore_changes`

---

### hetzner/server-stateless

Web/application servers designed for ephemeral workloads.

```hcl
module "web" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateless?ref=v1.9.0"

  name       = "web"
  type       = "cx22"
  network_id = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default

  # Optional
  zone            = "nbg1"
  instances_count = 3
  prevent_destroy = false

  # Optional audit account for new servers (requires v1.11.0 or later).
  audit_ssh_public_key = trimspace(file("~/.ssh/audit.pub"))

  # Accept HTTP and HTTPS only from these CIDR blocks (default: all addresses).
  # Port 937 (SSH) stays open to all. web_source_ips and per-rule source_ips
  # require v1.9.0 or later; older versions reject web_source_ips but silently
  # ignore per-rule source_ips, which opens that port to all addresses.
  web_source_ips = [
    "173.245.48.0/20", # Cloudflare ranges, abridged
    "2400:cb00::/32",
    "203.0.113.10/32", # monitoring
  ]

  additional_firewall_rules = [
    { protocol = "tcp", port = 9100, source_ips = ["203.0.113.20/32"] }, # node exporter, monitoring host
  ]
}
```

A server that serves no web traffic, such as a background worker, can drop ports
80 and 443 so its firewall holds only SSH plus its additional rules
(`web_ports_enabled` requires v1.12.0 or later; older versions reject it):

```hcl
module "worker" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/server-stateless?ref=v1.12.0"

  name       = "worker"
  type       = "cx22"
  network_id = module.network.vpc_id
  ssh_key_resource = hcloud_ssh_key.default

  # Firewall: port 937 (SSH) from all addresses, then the rules below.
  web_ports_enabled = false

  additional_firewall_rules = [
    { protocol = "tcp", port = 9100, source_ips = ["203.0.113.20/32"] }, # node exporter, monitoring host
  ]
}
```

| Variable                    | Required | Default                  | Description                                  |
|-----------------------------|----------|--------------------------|----------------------------------------------|
| `name`                      | yes      | -                        | Name identifier                              |
| `type`                      | yes      | -                        | Server type                                  |
| `network_id`                | yes      | -                        | VPC ID from network module                   |
| `ssh_key_resource`          | yes      | -                        | hcloud_ssh_key resource                      |
| `zone`                      | no       | `nbg1`                   | Datacenter                                   |
| `instances_count`           | no       | `1`                      | Number of servers                            |
| `os`                        | no       | `ubuntu-24.04`           | OS image                                     |
| `prevent_destroy`           | no       | `false`                  | Enable delete protection                     |
| `web_ports_enabled`         | no       | `true`                   | Open ports 80 and 443 (see below)            |
| `web_source_ips`            | no       | `["0.0.0.0/0", "::/0"]`  | CIDR blocks allowed on ports 80 and 443      |
| `additional_firewall_rules` | no       | `[]`                     | Extra rules to open (see below)              |
| `audit_ssh_public_key`      | no       | `null`                   | Audit account key (see below)                |

| Output       | Description                   |
|--------------|-------------------------------|
| `server_ips` | List of public IPv4 addresses |

**Notes:**

- No automatic backups (unlike stateful)
- Base firewall opens ports 80 and 443 to `web_source_ips` (all addresses by default)
  and port 937 (SSH) to all addresses
- `web_ports_enabled = false` omits the 80 and 443 rules and ignores `web_source_ips`;
  the firewall then holds port 937 (SSH, all addresses) followed by
  `additional_firewall_rules`. The default renders the same rules as v1.11.0
- Each `additional_firewall_rules` entry takes `protocol`, `port` and an optional
  `source_ips` list of CIDR blocks (see [hetzner/firewall](#hetznerfirewall)); without
  `source_ips` the rule accepts `0.0.0.0/0` and `::/0`. `source_ips` requires v1.9.0
  or later: older versions silently ignore it and open the port to all addresses.
- `audit_ssh_public_key` adds a locked `audit` account to cloud-init (see
  [Audit account](#audit-account)); it only affects newly created servers, since
  `user_data` is in `ignore_changes`

---

### hetzner/object-storage

S3-compatible object storage buckets, each with an optional bucket policy and CORS rules.
The module configures the `aminueza/minio` provider (3.44 or later) with
`s3_compat_mode = true`, which the provider requires on non-MinIO backends.

```hcl
module "storage" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/hetzner/object-storage?ref=v1.10.0"

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
    # Objects readable by URL, bucket not listable, browser uploads from the app.
    uploads = {
      name = "myapp-uploads"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = { AWS = ["*"] }
          Action    = ["s3:GetObject"]
          Resource  = ["arn:aws:s3:::myapp-uploads/*"]
        }]
      })
      cors_rules = [{
        allowed_origins = ["https://app.example.com"]
        allowed_methods = ["PUT"]
        allowed_headers = ["content-type"]
      }]
    }
  }
}
```

| Variable        | Required | Default | Description                           |
|-----------------|----------|---------|---------------------------------------|
| `s3_access_key` | yes      | -       | S3 access key                         |
| `s3_secret_key` | yes      | -       | S3 secret key                         |
| `buckets`       | yes      | -       | Map of bucket definitions (see below) |
| `zone`          | no       | `nbg1`  | Object storage region                 |

Bucket fields:

- `name` (required): bucket name
- `acl` (optional, default `private`): `private`, `public-read` or `public-read-write`.
  The provider's `acl` is not an S3 ACL but a canned bucket policy: `public-read` writes
  one that also grants `s3:ListBucket`, so anyone can list the bucket's objects.
- `policy` (optional): bucket policy as a JSON object, such as the output of
  `jsonencode()`. It requires `acl = "private"`, because any other `acl` writes the same
  bucket policy. Use it for access `acl` cannot express, such as `s3:GetObject` without
  `s3:ListBucket`.
- `cors_rules` (optional, default `[]`): CORS rules, each with `allowed_origins` and
  `allowed_methods` (`GET`, `PUT`, `POST`, `DELETE`, `HEAD`) and optional
  `allowed_headers`, `expose_headers` and `max_age_seconds`.

`policy` and `cors_rules` require v1.10.0 or later; older versions silently ignore them.

| Output               | Description                              |
|----------------------|------------------------------------------|
| `bucket_names`       | Map of bucket names                      |
| `bucket_urls`        | Map of bucket domain URLs                |
| `public_bucket_urls` | URLs for public buckets by `acl` (below) |
| `endpoint`           | S3 endpoint URL                          |

`public_bucket_urls` lists only `public-read` and `public-read-write` buckets: a bucket
made public by its `policy` keeps `acl = "private"` and is not included.

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

### cloudflare/redirect

Per-host URL redirects implemented as a Cloudflare **Single Redirects** ruleset (`http_request_dynamic_redirect` phase, zone-scoped). Use this to retire a domain by 301-ing some or all of its hosts to a replacement, preserving path and query string. Each map entry produces one rule inside a single ruleset.

```hcl
module "redirect" {
  source = "git::https://github.com/marcortola/terraform-modules.git//modules/cloudflare/redirect?ref=v1.6.0"

  token = var.cloudflare_token
  zone  = "old-domain.com"
  name  = "old-domain"

  rules = {
    apex = {
      source_host = "@"
      target_url  = "https://new-domain.com"
    }
    www = {
      source_host = "www"
      target_url  = "https://new-domain.com"
    }
    clubs = {
      source_host = "clubs"
      target_url  = "https://clubs.new-domain.com"
    }
    api = {
      source_host     = "api"
      target_url      = "https://api.new-domain.com"
      placeholder_dns = true # host has no real origin; module creates the proxied record
    }
  }
}
```

| Variable  | Required | Default | Description                                |
|-----------|----------|---------|--------------------------------------------|
| `token`   | yes      | -       | Cloudflare API token                       |
| `zone`    | yes      | -       | Source domain (the one to redirect from)   |
| `name`    | yes      | -       | Resource identifier                        |
| `rules`   | no       | `{}`    | Map of redirect rules                      |

Rule fields:

- `source_host` (required): subdomain label (e.g. `www`) or `@` for the apex
- `target_url` (required): absolute destination URL (e.g. `https://new-domain.com`)
- `preserve_path` (optional, default `true`): append the original path to `target_url`
- `preserve_query` (optional, default `true`): forward the original query string
- `status_code` (optional, default `301`): HTTP redirect status (301, 302, 307, 308)
- `placeholder_dns` (optional, default `false`): when `true`, the module creates a proxied A record for `source_host` pointing at `192.0.2.1`, so the redirect fires for a host with no real origin (see notes). Leave `false` for any host that already resolves to a real origin — otherwise the placeholder collides with the existing record.

**Notes:**

- Cloudflare allows only **one ruleset per zone per phase** — do not instantiate this module twice against the same `zone`.
- The host must be **proxied** (orange-cloud) at the DNS layer for the redirect to fire. A Dynamic Redirect rule only acts on traffic Cloudflare actually proxies. For a host with no real origin, set `placeholder_dns = true` and the module creates a proxied A record at `192.0.2.1` (RFC 5737 TEST-NET) for you — unroutable, never contacted, but enough to route the request through the edge where the redirect short-circuits it. (Equivalently you can create that record yourself in the `cloudflare/dns` module and leave `placeholder_dns = false`.)
- Using `placeholder_dns = true` requires the API token to also hold **`Zone → DNS → Edit`** on the source zone, in addition to the Single Redirect permission below.
- Do not set `placeholder_dns = true` for `source_host = "@"` (apex) when the zone already has an apex record — the placeholder will collide with it.
- The rule fires before origin: no backend is contacted.
- Use `preserve_path = false` together with a fully-qualified `target_url` (e.g. `https://new-domain.com/welcome`) when you want every request on the source host to land on a fixed path.
- **Required Cloudflare API token permission:** `Zone → Single Redirect → Edit` on the source zone, with Zone Resources scoped to include that zone. Without it, `terraform apply` fails with `request is not authorized`. (`Zone → Config Rules`, `Zone → Transform Rules`, and `Zone → WAF` permissions do NOT cover the `http_request_dynamic_redirect` phase used by this module.)

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

### Audit account

Both server modules take an optional `audit_ssh_public_key` (v1.11.0 or later). It must
be a single line starting with `ssh-`, with no newline, so wrap `file()` in `trimspace()`.
When it is set, cloud-init also:

- Creates an `audit` user with a locked password, shell `/bin/sh`, no supplementary groups and no sudo
  rule. The shell is a real one because sshd runs a forced command through the login
  shell; `nologin` would refuse it.
- Installs the key as that user's only authorized key, restricted to a forced command:

  ```text
  restrict,command="/usr/local/bin/infra-audit-dispatch" ssh-ed25519 AAAA... comment
  ```

- Writes `AllowUsers kamal audit` to `sshd_config` instead of `AllowUsers kamal`.

The modules do not install `/usr/local/bin/infra-audit-dispatch`, the scripts it runs, or
any sudoers rules they need; those come from the consumer's own installer. Until that
installer runs, every `audit` login fails closed because the forced command does not exist.

Like the rest of cloud-init, this only takes effect on newly created servers: `user_data`
is in `ignore_changes`, so setting or changing the key never touches existing servers.
With the variable unset, the rendered cloud-init is byte-identical to v1.10.0's.

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
