locals {
  # Exposed as a local so the module tests can assert on the rendered text.
  shared_cloud_config = templatefile("${path.module}/../../../cloudinit/shared.tpl", {
    ssh_authorized_key   = var.ssh_key_resource.public_key
    audit_ssh_public_key = var.audit_ssh_public_key
  })

  # web_ports_enabled = false omits 80 and 443 and ignores web_source_ips, so the
  # firewall holds only 937 plus additional_firewall_rules (for example a worker).
  # With the default the order stays 80, 443, 937.
  web_firewall_rules = var.web_ports_enabled ? [
    {
      protocol   = "tcp"
      port       = 80
      source_ips = var.web_source_ips
    },
    {
      protocol   = "tcp"
      port       = 443
      source_ips = var.web_source_ips
    },
  ] : []

  # Port 937 (SSH) keeps the firewall module's default sources: all IPv4 and IPv6 addresses.
  base_firewall_rules = concat(local.web_firewall_rules, [
    {
      protocol   = "tcp"
      port       = 937
      source_ips = null
    }
  ])

  all_firewall_rules = concat(local.base_firewall_rules, var.additional_firewall_rules)
}

resource "hcloud_server" "server" {
  count        = var.instances_count
  name         = "${var.name}-stateless-${count.index + 1}"
  location     = var.zone
  server_type  = var.type
  image        = var.os
  ssh_keys     = [var.ssh_key_resource.id]
  firewall_ids = [module.firewall.ingress_id]

  keep_disk = var.keep_disk_size_to_allow_downgrades

  user_data = data.cloudinit_config.data_cloudinit_config_server.rendered

  depends_on = [
    module.firewall,
  ]

  public_net {
    ipv4_enabled = true
    # See: https://docs.saltbox.dev/faq/Hetzner/
    ipv6_enabled = false
  }

  network {
    network_id = var.network_id
    ip         = length(var.network_ips) > 0 ? var.network_ips[count.index] : null
    alias_ips  = []
  }

  delete_protection  = var.prevent_destroy
  rebuild_protection = var.prevent_destroy

  lifecycle {
    ignore_changes = [user_data]
  }
}

module "firewall" {
  source = "../firewall"
  name   = "${var.name}-server-stateless"
  rule   = local.all_firewall_rules
}

data "cloudinit_config" "data_cloudinit_config_server" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = local.shared_cloud_config
  }

  part {
    content_type = "text/cloud-config"
    content      = file("${path.module}/../../../cloudinit/server.yml")
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }

  dynamic "part" {
    for_each = var.additional_cloudinit_parts
    content {
      content_type = part.value.content_type
      content      = part.value.content
      merge_type   = part.value.merge_type
    }
  }
}
