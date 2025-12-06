locals {
  base_firewall_rules = [
    {
      protocol = "tcp"
      port     = 937
    }
  ]

  all_firewall_rules = concat(local.base_firewall_rules, var.additional_firewall_rules)
}

resource "hcloud_server" "server" {
  count       = var.instances_count
  name        = "${var.name}-stateful-${count.index + 1}"
  location    = var.zone
  server_type = var.type
  image       = var.os
  ssh_keys = [var.ssh_key_resource.id]
  firewall_ids = [module.firewall.ingress_id]

  keep_disk = var.keep_disk_size_to_allow_downgrades
  backups   = var.enable_backups

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
    alias_ips = []
  }

  delete_protection  = true
  rebuild_protection = true

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      user_data,
      image,
    ]
  }
}

module "firewall" {
  source = "../firewall"
  name   = "${var.name}-server-stateful"
  rule   = local.all_firewall_rules
}

data "cloudinit_config" "data_cloudinit_config_server" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/../../../cloudinit/shared.tpl", {
      ssh_authorized_key = var.ssh_key_resource.public_key
    })
  }

  part {
    content_type = "text/cloud-config"
    content = file("${path.module}/../../../cloudinit/server.yml")
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }
}
