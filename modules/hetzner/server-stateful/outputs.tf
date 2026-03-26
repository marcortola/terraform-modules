output "server_ips" {
  value = hcloud_server.server[*].ipv4_address
}

output "server_private_ips" {
  value = hcloud_server.server[*].network[0].ip
}