provider "cloudflare" {
  api_token = var.token
}

data "cloudflare_zones" "data_redirect_zones" {
  filter {
    name = var.zone
  }
}

resource "cloudflare_ruleset" "redirects" {
  zone_id     = lookup(data.cloudflare_zones.data_redirect_zones.zones[0], "id")
  name        = "${var.name}-redirects"
  description = "Single Redirects for ${var.zone}"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  dynamic "rules" {
    for_each = var.rules
    content {
      ref         = rules.key
      action      = "redirect"
      description = "Redirect ${rules.value.source_host == "@" ? var.zone : "${rules.value.source_host}.${var.zone}"} -> ${rules.value.target_url}"
      expression  = format("(http.host eq %q)", rules.value.source_host == "@" ? var.zone : "${rules.value.source_host}.${var.zone}")

      action_parameters {
        from_value {
          status_code           = rules.value.status_code
          preserve_query_string = rules.value.preserve_query

          target_url {
            expression = rules.value.preserve_path ? format("concat(%q, http.request.uri.path)", rules.value.target_url) : format("%q", rules.value.target_url)
          }
        }
      }
    }
  }
}
