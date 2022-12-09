module "this" {
  source = "../"

  # OrganizationID
  principalOrgId = "NEED_TO_BE_INSERTED"

  # Vault
  vault_name = "awsbackup-vault"

  # Plan
  plan_name = "tagging-plans"

  #IAM Role name
  iam_role_name = "AWSBackupRole"

  #Notifications

  # resource "aws_sns_topic" "backup_vault_notifications" {
  #   name = "backup_notifications"
  # }

  # notifications = { # Not sure if already exists a topic for notifications.
  #   sns_topic_arn       = aws_sns_topic.backup_vault_notifications.arn
  #   backup_vault_events = ["BACKUP_JOB_FAILED", "RESTORE_JOB_COMPLETED"]
  # }

  # Multiple rules using a list of maps
  rules = [
    {
      name              = "daily-backup"
      schedule          = "cron(0 12 * * ? *)"
      target_vault_name = var.vault_name
      start_window      = 120
      completion_window = 360
      lifecycle = {
        cold_storage_after = 0
        delete_after       = 7
      },
      recovery_point_tags = {
        aws-backup = "daily"
      }
    },
    {
      name                = "weekly-backup"
      schedule            = "cron(0 3 * * SUN)"
      target_vault_name   = var.vault_name
      start_window        = 120
      completion_window   = 360
      lifecycle           = {
        cold_storage_after = 0
        delete_after       = 30
      }
      copy_actions        = [] # To be implemented
      recovery_point_tags = {
        aws-backup = "weekly"
      }
    },
    {
      name                = "monthly-backup"
      schedule            = "cron(0 3 1 * *)"
      target_vault_name   = var.vault_name
      start_window        = 120
      completion_window   = 360
      lifecycle           = {
        cold_storage_after = 0
        delete_after       = 365
      }
      copy_actions        = [] # To be implemented
      recovery_point_tags = {
        backup = "monthly"
      }
    }
  ]

  # Multiple selections
  #  - Selection-1: By tags: Environment = prod, Owner = devops
  selections = [
    {
      name = "tagging-backup"
      selection_tags = [
        {
          type  = "STRINGEQUALS"
          key   = "backup"
          value = "True"
        }
      ]
    }
  ]

  tags = {
    Owner       = "backup-aws"
    Environment = "prod"
    Terraform   = true
  }
}