# Plan-only tests for the server's firewall rules. Needs Terraform 1.7+ for mock_provider.

mock_provider "hcloud" {}
mock_provider "cloudinit" {}

variables {
  name       = "test"
  type       = "cx22"
  network_id = "1"
  ssh_key_resource = {
    id         = "1"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly test"
  }
}

# A call shaped like the v1.8.0 callers: no web_source_ips, additional rules without
# source_ips. The rendered rules must match what v1.8.0 produced, in the same order.
run "v1_8_0_style_call_renders_unchanged_rules" {
  command = plan

  variables {
    additional_firewall_rules = [
      { protocol = "tcp", port = 51432 },
      { protocol = "tcp", port = 55672 },
    ]
  }

  assert {
    condition     = [for r in local.all_firewall_rules : r.port] == [80, 443, 937, 51432, 55672]
    error_message = "Rule order must stay base rules (80, 443, 937) followed by the additional rules."
  }

  assert {
    condition = toset([for r in module.firewall.rules : {
      direction  = r.direction
      protocol   = r.protocol
      port       = r.port
      source_ips = r.source_ips
      }]) == toset([for port in ["80", "443", "937", "51432", "55672"] : {
      direction  = "in"
      protocol   = "tcp"
      port       = port
      source_ips = toset(["0.0.0.0/0", "::/0"])
    }])
    error_message = "Without overrides every rule must be inbound TCP from 0.0.0.0/0 and ::/0, as in v1.8.0."
  }
}

run "defaults_open_base_rules_to_all" {
  command = plan

  assert {
    condition     = length(module.firewall.rules) == 3
    error_message = "Expected exactly the three base rules."
  }

  assert {
    condition     = alltrue([for r in module.firewall.rules : r.source_ips == toset(["0.0.0.0/0", "::/0"])])
    error_message = "Base rules must accept 0.0.0.0/0 and ::/0 by default."
  }
}

run "web_source_ips_restrict_only_http_and_https" {
  command = plan

  variables {
    web_source_ips = ["173.245.48.0/20", "2400:cb00::/32", "203.0.113.10/32"]
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "80"]) == toset(["173.245.48.0/20", "2400:cb00::/32", "203.0.113.10/32"])
    error_message = "Port 80 must accept only web_source_ips."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "443"]) == toset(["173.245.48.0/20", "2400:cb00::/32", "203.0.113.10/32"])
    error_message = "Port 443 must accept only web_source_ips."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "937"]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "Port 937 (SSH) must stay open to all addresses."
  }
}

run "null_web_source_ips_keeps_default" {
  command = plan

  variables {
    web_source_ips = null
  }

  assert {
    condition     = alltrue([for r in module.firewall.rules : r.source_ips == toset(["0.0.0.0/0", "::/0"])])
    error_message = "A null web_source_ips must keep the base rules open to all."
  }
}

run "additional_rules_with_and_without_source_ips" {
  command = plan

  variables {
    web_source_ips = ["173.245.48.0/20"]
    additional_firewall_rules = [
      { protocol = "tcp", port = 9100, source_ips = ["10.0.0.5/32"] },
      { protocol = "udp", port = 51820 },
    ]
  }

  assert {
    condition     = length(module.firewall.rules) == 5
    error_message = "Expected the three base rules plus two additional rules."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "9100"]) == toset(["10.0.0.5/32"])
    error_message = "An additional rule with source_ips must accept only those sources."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "51820" && r.protocol == "udp"]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "An additional rule without source_ips must accept 0.0.0.0/0 and ::/0."
  }

  assert {
    condition     = one([for r in module.firewall.rules : r.source_ips if r.port == "937"]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "Port 937 (SSH) must stay open to all addresses."
  }
}

# A worker serves no web traffic: with enable_web_ports = false the firewall holds
# only port 937 (SSH), open to all addresses.
run "web_ports_disabled_renders_only_ssh" {
  command = plan

  variables {
    enable_web_ports = false
  }

  assert {
    condition     = [for r in local.all_firewall_rules : r.port] == [937]
    error_message = "Without web ports the only rule must be 937."
  }

  assert {
    condition = toset([for r in module.firewall.rules : {
      direction  = r.direction
      protocol   = r.protocol
      port       = r.port
      source_ips = r.source_ips
      }]) == toset([{
      direction  = "in"
      protocol   = "tcp"
      port       = "937"
      source_ips = toset(["0.0.0.0/0", "::/0"])
    }])
    error_message = "Without web ports the firewall must hold exactly inbound TCP 937 from 0.0.0.0/0 and ::/0."
  }
}

run "web_ports_disabled_keeps_additional_rules_in_order" {
  command = plan

  variables {
    enable_web_ports = false
    additional_firewall_rules = [
      { protocol = "tcp", port = 9100, source_ips = ["10.0.0.5/32"] },
      { protocol = "udp", port = 51820 },
    ]
  }

  assert {
    condition     = [for r in local.all_firewall_rules : r.port] == [937, 9100, 51820]
    error_message = "Without web ports the rules must be 937 followed by the additional rules, in order."
  }

  assert {
    condition = toset([for r in module.firewall.rules : {
      direction  = r.direction
      protocol   = r.protocol
      port       = r.port
      source_ips = r.source_ips
      }]) == toset([
      { direction = "in", protocol = "tcp", port = "937", source_ips = toset(["0.0.0.0/0", "::/0"]) },
      { direction = "in", protocol = "tcp", port = "9100", source_ips = toset(["10.0.0.5/32"]) },
      { direction = "in", protocol = "udp", port = "51820", source_ips = toset(["0.0.0.0/0", "::/0"]) },
    ])
    error_message = "Without web ports the firewall must hold 937 plus the additional rules with their own sources."
  }
}

run "web_ports_disabled_ignores_web_source_ips" {
  command = plan

  variables {
    enable_web_ports = false
    web_source_ips   = ["173.245.48.0/20", "203.0.113.10/32"]
  }

  assert {
    condition     = [for r in module.firewall.rules : r.port] == ["937"]
    error_message = "web_source_ips must not bring back ports 80 or 443 when web ports are disabled."
  }

  assert {
    condition     = alltrue([for r in module.firewall.rules : !contains(r.source_ips, "173.245.48.0/20") && !contains(r.source_ips, "203.0.113.10/32")])
    error_message = "No rule may accept web_source_ips when web ports are disabled."
  }
}

run "null_enable_web_ports_keeps_web_ports" {
  command = plan

  variables {
    enable_web_ports = null
  }

  assert {
    condition     = [for r in local.all_firewall_rules : r.port] == [80, 443, 937]
    error_message = "A null enable_web_ports must keep the default base rules (80, 443, 937)."
  }
}
