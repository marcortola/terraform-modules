# Plan-only tests for the server's firewall rules. Needs Terraform 1.7+ for mock_provider.

mock_provider "hcloud" {}
mock_provider "cloudinit" {}

variables {
  name       = "test"
  type       = "cx32"
  network_id = "1"
  ssh_key_resource = {
    id         = "1"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly test"
  }
}

# A call shaped like the v1.8.0 callers: additional rules without source_ips.
run "v1_8_0_style_call_renders_unchanged_rules" {
  command = plan

  variables {
    additional_firewall_rules = [
      { protocol = "tcp", port = 51432 },
      { protocol = "tcp", port = 55672 },
    ]
  }

  assert {
    condition     = [for r in local.all_firewall_rules : r.port] == [937, 51432, 55672]
    error_message = "Rule order must stay the base rule (937) followed by the additional rules."
  }

  assert {
    condition     = alltrue([for r in module.firewall.rules : r.source_ips == toset(["0.0.0.0/0", "::/0"])])
    error_message = "Without source_ips every rule must accept 0.0.0.0/0 and ::/0, as in v1.8.0."
  }
}

run "additional_rules_with_and_without_source_ips" {
  command = plan

  variables {
    additional_firewall_rules = [
      { protocol = "tcp", port = 443, source_ips = ["173.245.48.0/20", "203.0.113.10/32"] },
      { protocol = "tcp", port = 80 },
    ]
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "443"]) == toset(["173.245.48.0/20", "203.0.113.10/32"])
    error_message = "An additional rule with source_ips must accept only those sources."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "80"]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "An additional rule without source_ips must accept 0.0.0.0/0 and ::/0."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "937"]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "Port 937 (SSH) must stay open to all addresses."
  }
}
