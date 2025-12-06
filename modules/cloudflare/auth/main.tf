provider "cloudflare" {
  api_token = var.token
}

data "cloudflare_accounts" "accounts" {

}

data "cloudflare_zones" "data_zones" {
  filter {
    account_id = data.cloudflare_accounts.accounts.accounts[0].id
    name       = var.zone
    status     = "active"
  }
}

resource "cloudflare_workers_script" "auth_noindex_worker_script" {
  account_id = data.cloudflare_accounts.accounts.accounts[0].id
  name = replace(replace(replace("${var.zone}_basic-auth-noindex", "/[^a-zA-Z_]/", "_"), "/_+/", "_"), "/^_+|_+$/", "")
  content    = "${file("${path.module}/cf-workers/auth-noindex-worker.js")}"

  secret_text_binding {
    name = "shared_auth_user"
    text = var.shared_auth_user
  }

  secret_text_binding {
    name = "shared_auth_password"
    text = var.shared_auth_password
  }
}

resource "cloudflare_workers_script" "auth_only_worker_script" {
  account_id = data.cloudflare_accounts.accounts.accounts[0].id
  name = replace(replace(replace("${var.zone}_basic-auth-only", "/[^a-zA-Z_]/", "_"), "/_+/", "_"), "/^_+|_+$/", "")
  content    = "${file("${path.module}/cf-workers/auth-only-worker.js")}"

  secret_text_binding {
    name = "shared_auth_user"
    text = var.shared_auth_user
  }

  secret_text_binding {
    name = "shared_auth_password"
    text = var.shared_auth_password
  }
}

resource "cloudflare_workers_script" "noindex_only_worker_script" {
  account_id = data.cloudflare_accounts.accounts.accounts[0].id
  name = replace(replace(replace("${var.zone}_noindex-only", "/[^a-zA-Z_]/", "_"), "/_+/", "_"), "/^_+|_+$/", "")
  content    = "${file("${path.module}/cf-workers/noindex-only-worker.js")}"
}

resource "cloudflare_workers_route" "http_basic_auth_catch_all_route" {
  zone_id = lookup(data.cloudflare_zones.data_zones.zones[0], "id")

  for_each = {
    for index, subdomain_definition in var.protected_subdomains : index => subdomain_definition
  }

  pattern = "${each.value.name}.${var.zone}/*"

  script_name = lookup({
    "true:true"   = cloudflare_workers_script.auth_noindex_worker_script.name
    "true:false"  = cloudflare_workers_script.auth_only_worker_script.name
    "false:true"  = cloudflare_workers_script.noindex_only_worker_script.name
  }, "${each.value.auth}:${each.value.noindex}")
}