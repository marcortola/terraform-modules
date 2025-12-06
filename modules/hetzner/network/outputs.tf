output "vpc_id" {
  description = "The ID of the VPC"
  value       = hcloud_network.vpc.id
}

output "vpc_subnet_id" {
  description = "The ID of the VPC subnetwork"
  value       = hcloud_network_subnet.vpc_subnet.id
}