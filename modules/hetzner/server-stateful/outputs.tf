output "server_ips" {
  value = hcloud_server.server[*].ipv4_address
}

output "server_private_ips" {
  value = [for s in hcloud_server.server : one(s.network).ip]
}