output "ingress_id" {
  value = hcloud_firewall.ingress.id
}

output "rules" {
  description = "Inbound rules as rendered on the firewall, each with direction, protocol, port and source_ips"
  value       = hcloud_firewall.ingress.rule
}
