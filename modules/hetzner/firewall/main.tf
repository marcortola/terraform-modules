resource "hcloud_firewall" "ingress" {
  name = "${var.name}-firewall-ingress"

  dynamic "rule" {
    for_each = var.rule

    content {
      direction  = "in"
      protocol   = rule.value.protocol
      port       = rule.value.port
      source_ips = rule.value.source_ips
    }
  }

  dynamic "apply_to" {
    for_each = var.apply_to

    content {
      label_selector = apply_to.value.label_selector
      server         = apply_to.value.server
    }
  }
}
