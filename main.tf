data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# AWS Backup vault
resource "aws_iam_policy_document" "backup-key-policies" {
  statement {
    actions = ["kms:*"]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext"
    ]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.iam_role_name}"]
    }

    condition {
      test = "StringEquals"
      variable = "kms:ViaService"
      value = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "backup-key" {
  enable_key_rotation = true
  policy = aws_iam_policy_document.backup-key-policies
}

resource "aws_kms_alias" "backup-key-alias" {
  name          = "alias/${var.kms_alias}"
  target_key_id = aws_kms_key.backup-key.key_id
}

# Backup vault and the policy
resource "aws_backup_vault" "ab_vault" {
  count       = var.enabled && var.vault_name != null ? 1 : 0
  name        = var.vault_name
  kms_key_arn = aws_kms_key.backup-key
  tags        = var.tags
}

resource "aws_backup_vault_policy" "example" {
  backup_vault_name = aws_backup_vault.example.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "default",
  "Statement": [
    {
      "Sid": "Allow acces to backup vault",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "CopyIntoBackupVault"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {"aws:PrincipalOrgId": ${var.principalOrgId}}
      }

    }
  ]
}
POLICY
}

# AWS Backup plan
resource "aws_backup_plan" "ab_plan" {
  count = var.enabled ? 1 : 0
  name  = var.plan_name

  # Rules (Move to use Backup Plan centralized, via console)
  dynamic "rule" {
    for_each = local.rules
    content {
      rule_name                = lookup(rule.value, "name", null)
      target_vault_name        = lookup(rule.value, "target_vault_name", null) != null ? rule.value.target_vault_name : var.vault_name != null ? var.vault_name : "Default"
      schedule                 = lookup(rule.value, "schedule", null)
      start_window             = lookup(rule.value, "start_window", null)
      completion_window        = lookup(rule.value, "completion_window", null)
      enable_continuous_backup = lookup(rule.value, "enable_continuous_backup", null)
      recovery_point_tags      = length(lookup(rule.value, "recovery_point_tags", {})) == 0 ? var.tags : lookup(rule.value, "recovery_point_tags")

      # Lifecycle
      dynamic "lifecycle" {
        for_each = length(lookup(rule.value, "lifecycle", {})) == 0 ? [] : [lookup(rule.value, "lifecycle", {})]
        content {
          cold_storage_after = lookup(lifecycle.value, "cold_storage_after", 0)
          delete_after       = lookup(lifecycle.value, "delete_after", 90)
        }
      }

      # Copy action
      dynamic "copy_action" {
        for_each = lookup(rule.value, "copy_actions", [])
        content {
          destination_vault_arn = lookup(copy_action.value, "destination_vault_arn", null)

          # Copy Action Lifecycle
          dynamic "lifecycle" {
            for_each = length(lookup(copy_action.value, "lifecycle", {})) == 0 ? [] : [lookup(copy_action.value, "lifecycle", {})]
            content {
              cold_storage_after = lookup(lifecycle.value, "cold_storage_after", 0)
              delete_after       = lookup(lifecycle.value, "delete_after", 90)
            }
          }
        }
      }
    }
  }

  # Advanced backup setting
  dynamic "advanced_backup_setting" {
    for_each = var.windows_vss_backup ? [1] : []
    content {
      backup_options = {
        WindowsVSS = "enabled"
      }
      resource_type = "EC2"
    }
  }

  # Tags
  tags = var.tags

  # First create the vault if needed
  depends_on = [aws_backup_vault.ab_vault]
}

locals {

  # Rule
  rule = var.rule_name == null ? [] : [
    {
      name              = var.rule_name
      target_vault_name = var.vault_name != null ? var.vault_name : "Default"
      schedule          = var.rule_schedule
      start_window      = var.rule_start_window
      completion_window = var.rule_completion_window
      lifecycle = var.rule_lifecycle_cold_storage_after == null ? {} : {
        cold_storage_after = var.rule_lifecycle_cold_storage_after
        delete_after       = var.rule_lifecycle_delete_after
      }
      enable_continuous_backup = var.rule_enable_continuous_backup
      recovery_point_tags      = var.rule_recovery_point_tags
    }
  ]

  # Rules
  rules = concat(local.rule, var.rules)

}