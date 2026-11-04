# Plan-only tests for per-rule source_ips. Needs Terraform 1.7+ for mock_provider.

mock_provider "hcloud" {}

variables {
  name = "test"
}

run "defaults_open_every_rule_to_all" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 80 },
      { protocol = "tcp", port = 443 },
      { protocol = "tcp", port = 937 },
    ]
  }

  assert {
    condition     = length(hcloud_firewall.ingress.rule) == 3
    error_message = "Expected one firewall rule per input rule."
  }

  assert {
    condition     = alltrue([for r in hcloud_firewall.ingress.rule : r.source_ips == toset(["0.0.0.0/0", "::/0"])])
    error_message = "Rules without source_ips must accept 0.0.0.0/0 and ::/0."
  }

  assert {
    condition     = alltrue([for r in hcloud_firewall.ingress.rule : r.direction == "in"])
    error_message = "Every rule must be inbound."
  }
}

run "null_source_ips_falls_back_to_default" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 937, source_ips = null },
    ]
  }

  assert {
    condition     = one([for r in hcloud_firewall.ingress.rule : r.source_ips]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "A null source_ips must fall back to 0.0.0.0/0 and ::/0."
  }
}

run "custom_source_ips_apply_only_to_their_rule" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = ["173.245.48.0/20", "2400:cb00::/32"] },
      { protocol = "tcp", port = 937 },
    ]
  }

  assert {
    condition     = one([for r in hcloud_firewall.ingress.rule : r.source_ips if r.port == "443"]) == toset(["173.245.48.0/20", "2400:cb00::/32"])
    error_message = "Port 443 must accept only its custom source_ips."
  }

  assert {
    condition     = one([for r in hcloud_firewall.ingress.rule : r.source_ips if r.port == "937"]) == toset(["0.0.0.0/0", "::/0"])
    error_message = "Port 937 must keep the default sources."
  }

  assert {
    condition     = output.rules == hcloud_firewall.ingress.rule
    error_message = "The rules output must expose the rendered firewall rules."
  }
}

run "rejects_empty_source_ips" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = [] },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_source_ip_without_prefix" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = ["203.0.113.10"] },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_ipv4_cidr_with_host_bits" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = ["10.0.0.5/24"] },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_ipv6_cidr_with_host_bits" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = ["2001:db8::1/32"] },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_non_canonical_ipv6" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = ["2001:DB8::/32"] },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_one_bad_entry_among_valid_ones" {
  command = plan

  variables {
    rule = [
      { protocol = "tcp", port = 443, source_ips = ["173.245.48.0/20", "173.245.48.1/20"] },
    ]
  }

  expect_failures = [var.rule]
}

run "accepts_cloudflare_ranges_and_host_routes" {
  command = plan

  variables {
    rule = [
      {
        protocol = "tcp"
        port     = 443
        source_ips = [
          "173.245.48.0/20", "103.21.244.0/22", "2400:cb00::/32", "2606:4700::/32",
          "2a06:98c0::/29", "203.0.113.10/32", "2001:db8::1/128",
        ]
      },
    ]
  }

  assert {
    condition     = length(one(hcloud_firewall.ingress.rule).source_ips) == 7
    error_message = "Canonical network CIDRs, including /32 and /128 host routes, must be accepted."
  }
}
