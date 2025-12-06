resource "hcloud_network" "vpc" {
  name     = "${var.name}-network"
  ip_range = var.ip_range
}

resource "hcloud_network_subnet" "vpc_subnet" {
  network_id   = hcloud_network.vpc.id
  type         = "cloud"
  network_zone = var.zone
  ip_range = cidrsubnet(var.ip_range, 8, 0)

  depends_on = [
    hcloud_network.vpc
  ]
}