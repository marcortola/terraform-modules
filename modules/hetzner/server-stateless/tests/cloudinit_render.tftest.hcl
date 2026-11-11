# Plan-only tests for the shared cloud-init text (cloudinit/shared.tpl) this module renders.
# The cloudinit provider is mocked, so the tests assert on local.shared_cloud_config, the
# templatefile() result the module passes to the first cloud-config part.
# Needs Terraform 1.7+ for mock_provider.

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

# cloudinit/testdata/shared-v1.10.0.golden is v1.10.0's shared.tpl rendered with the key above.
run "audit_key_unset_renders_v1_10_0_text" {
  command = plan

  assert {
    condition     = local.shared_cloud_config == file("${path.module}/../../../cloudinit/testdata/shared-v1.10.0.golden")
    error_message = "Without audit_ssh_public_key the shared cloud-init must be byte-identical to v1.10.0's."
  }

  assert {
    condition     = data.cloudinit_config.data_cloudinit_config_server.part[0].content == local.shared_cloud_config
    error_message = "The first cloud-config part must carry the rendered shared template."
  }
}

run "audit_key_set_renders_locked_audit_user" {
  command = plan

  variables {
    audit_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit@example"
  }

  # The only differences from v1.10.0 are the audit user and the AllowUsers line.
  assert {
    condition = local.shared_cloud_config == replace(
      replace(
        file("${path.module}/../../../cloudinit/testdata/shared-v1.10.0.golden"),
        "      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly test\n\npackages:",
        join("\n", [
          "      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnly test",
          "  - name: audit",
          "    lock_passwd: true",
          "    shell: /bin/sh",
          "    ssh_authorized_keys:",
          "      - 'restrict,command=\"/usr/local/bin/infra-audit-dispatch\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit@example'",
          "",
          "packages:",
        ])
      ),
      "      AllowUsers kamal\n",
      "      AllowUsers kamal audit\n"
    )
    error_message = "With audit_ssh_public_key set, only the audit user and 'AllowUsers kamal audit' may be added to the v1.10.0 text."
  }

  # The parsed user has no groups and no sudo, and its only key carries the forced command.
  assert {
    condition = yamldecode(local.shared_cloud_config).users[2] == {
      name        = "audit"
      lock_passwd = true
      shell       = "/bin/sh"
      ssh_authorized_keys = [
        "restrict,command=\"/usr/local/bin/infra-audit-dispatch\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit@example",
      ]
    }
    error_message = "The audit user must be exactly: locked password, /bin/sh, no groups, no sudo, one forced-command key."
  }

  assert {
    condition     = yamldecode(local.shared_cloud_config).users[1].name == "kamal" && length(yamldecode(local.shared_cloud_config).users) == 3
    error_message = "The audit user must be added after kamal, leaving the default and kamal users in place."
  }

  assert {
    condition     = strcontains(yamldecode(local.shared_cloud_config).write_files[2].content, "\nAllowUsers kamal audit\n")
    error_message = "sshd_config must allow both kamal and audit."
  }
}

# A key comment with YAML-significant characters must reach authorized_keys verbatim.
run "audit_key_comment_with_quote_and_hash_stays_verbatim" {
  command = plan

  variables {
    audit_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly it's #1: audit"
  }

  assert {
    condition = yamldecode(local.shared_cloud_config).users[2].ssh_authorized_keys == [
      "restrict,command=\"/usr/local/bin/infra-audit-dispatch\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly it's #1: audit",
    ]
    error_message = "The audit key must be quoted so YAML keeps its comment verbatim."
  }
}

run "audit_key_without_ssh_prefix_is_rejected" {
  command = plan

  variables {
    audit_ssh_public_key = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIAuditKeyOnly audit"
  }

  expect_failures = [var.audit_ssh_public_key]
}

run "audit_key_with_options_prefix_is_rejected" {
  command = plan

  variables {
    audit_ssh_public_key = "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit"
  }

  expect_failures = [var.audit_ssh_public_key]
}

run "audit_key_with_embedded_newline_is_rejected" {
  command = plan

  variables {
    audit_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISecondKey extra"
  }

  expect_failures = [var.audit_ssh_public_key]
}

# file() of a .pub file keeps its trailing newline; callers must trimspace() it.
run "audit_key_with_trailing_newline_is_rejected" {
  command = plan

  variables {
    audit_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit\n"
  }

  expect_failures = [var.audit_ssh_public_key]
}

run "audit_key_with_control_character_is_rejected" {
  command = plan

  variables {
    audit_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditKeyOnly audit\u001b[0m"
  }

  expect_failures = [var.audit_ssh_public_key]
}

run "audit_key_empty_string_is_rejected" {
  command = plan

  variables {
    audit_ssh_public_key = ""
  }

  expect_failures = [var.audit_ssh_public_key]
}
