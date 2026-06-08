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

# Proxied placeholder origins for redirect-only hosts. A Dynamic Redirect rule only
# fires for traffic Cloudflare actually proxies, so a host with no real backend still
# needs a proxied DNS record. For each rule with placeholder_dns = true we create a
# proxied A record at 192.0.2.1 (RFC 5737 TEST-NET): unroutable, never contacted, but
# enough to route the request through the edge where the redirect short-circuits it.
# Leave placeholder_dns = false (default) for hosts that already resolve to a real origin.
resource "cloudflare_record" "redirect_placeholders" {
  for_each = { for k, v in var.rules : k => v if v.placeholder_dns }

  zone_id = lookup(data.cloudflare_zones.data_redirect_zones.zones[0], "id")
  name    = each.value.source_host
  type    = "A"
  content = "192.0.2.1"
  proxied = true
  ttl     = 1
  comment = "Placeholder origin for redirect rule '${each.key}' (no real backend)"
}
