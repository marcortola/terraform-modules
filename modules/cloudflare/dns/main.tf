provider "cloudflare" {
  api_token = var.token
}

data "cloudflare_zones" "data_dns_zones" {
  filter {
    name = var.zone
  }
}

resource "cloudflare_record" "dns_record" {
  for_each = {
    for index, value in var.records : index => value
  }

  zone_id = lookup(data.cloudflare_zones.data_dns_zones.zones[0], "id")
  name = coalesce(each.value.name, "@")
  content = each.value.value
  type    = each.value.type
  ttl     = each.value.ttl != null ? each.value.ttl : null
  proxied = each.value.proxied != null ? each.value.proxied : null
  priority = each.value.priority != null ? each.value.priority : null
}