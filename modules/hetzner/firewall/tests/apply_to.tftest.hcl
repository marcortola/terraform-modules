# Plan-only tests for attaching the firewall through apply_to. Needs Terraform 1.7+ for mock_provider.

mock_provider "hcloud" {}

variables {
  name = "test"
  rule = [
    { protocol = "tcp", port = 937 },
  ]
}

run "no_apply_to_attaches_nothing" {
  command = plan

  assert {
    condition     = length(hcloud_firewall.ingress.apply_to) == 0
    error_message = "Without apply_to the firewall must have no apply_to blocks, as the server modules expect."
  }
}

run "server_target_attaches_by_server_id" {
  command = plan

  variables {
    apply_to = [
      { server = 4242 },
    ]
  }

  assert {
    condition     = length(hcloud_firewall.ingress.apply_to) == 1
    error_message = "Expected one apply_to block per entry."
  }

  assert {
    condition     = one(hcloud_firewall.ingress.apply_to).server == 4242
    error_message = "The apply_to block must target server 4242."
  }
}

run "server_target_accepts_a_server_resource_id" {
  command = plan

  # hcloud_server.id is a string; the module converts it to the provider's number type.
  variables {
    apply_to = [
      { server = "4242" },
    ]
  }

  assert {
    condition     = one(hcloud_firewall.ingress.apply_to).server == 4242
    error_message = "A string server ID must be accepted and converted to a number."
  }
}

run "label_selector_target_attaches_by_label" {
  command = plan

  variables {
    apply_to = [
      { label_selector = "role=web" },
    ]
  }

  assert {
    condition     = length(hcloud_firewall.ingress.apply_to) == 1
    error_message = "Expected one apply_to block per entry."
  }

  assert {
    condition     = one(hcloud_firewall.ingress.apply_to).label_selector == "role=web"
    error_message = "The apply_to block must target the role=web label selector."
  }
}

run "mixed_targets_render_one_block_each" {
  # A set holding a block with an unset computed attribute has unknown length at plan
  # time, so this run applies against the mock provider to read the final set.
  command = apply

  variables {
    apply_to = [
      { server = 4242 },
      { label_selector = "role=web" },
    ]
  }

  assert {
    condition     = length(hcloud_firewall.ingress.apply_to) == 2
    error_message = "Expected one apply_to block per entry."
  }

  assert {
    condition     = contains([for a in hcloud_firewall.ingress.apply_to : a.server], 4242)
    error_message = "One apply_to block must target server 4242."
  }

  assert {
    condition     = contains([for a in hcloud_firewall.ingress.apply_to : a.label_selector], "role=web")
    error_message = "One apply_to block must target the role=web label selector."
  }
}

run "rejects_entry_with_both_targets" {
  command = plan

  variables {
    apply_to = [
      { server = 4242, label_selector = "role=web" },
    ]
  }

  expect_failures = [var.apply_to]
}

run "rejects_entry_without_target" {
  command = plan

  variables {
    apply_to = [
      {},
    ]
  }

  expect_failures = [var.apply_to]
}
