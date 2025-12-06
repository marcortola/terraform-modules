output "server_ips" {
  value = hcloud_server.server[*].ipv4_address
}