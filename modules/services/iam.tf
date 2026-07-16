# --- Collector IAM ---
# Execution role pulls images/logs and injects secrets; task role holds the
# runtime AWS permissions. Feature-gated policies are count-gated so a disabled
# feature never references an unpopulated secret or queue.

resource "aws_iam_role" "collector_execution" {
  name_prefix = "${var.name_prefix}-collector-exec-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "collector_execution" {
  role       = aws_iam_role.collector_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  collector_secret_arns = concat(
    [
      var.gateway_tenant_key_secret_arn,
      var.kiro_tenant_key_secret_arn,
      var.git_github_webhook_secret_arn,
      var.git_gitlab_webhook_token_secret_arn,
      var.collector_auth_token_secret_arn,
      var.collector_tls_cert_secret_arn,
      var.collector_tls_key_secret_arn,
      var.data_service_auth_token_secret_arn,
      var.data_service_tls_cert_secret_arn,
    ],
    local.export_enabled ? [var.export_tenant_key_secret_arn] : [],
    var.git_github_backfill_enabled ? [var.git_github_app_private_key_secret_arn] : [],
  )
}

resource "aws_iam_role_policy" "collector_execution_secrets" {
  name = "secrets-read"
  role = aws_iam_role.collector_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = "secretsmanager:GetSecretValue"
          Resource = local.collector_secret_arns
        }
      ],
      # The export tenant key may live under a customer CMK; module-owned
      # secrets use the AWS-managed key (no explicit kms grant needed).
      local.export_enabled ? [
        {
          Effect   = "Allow"
          Action   = "kms:Decrypt"
          Resource = "*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com"
            }
          }
        }
      ] : [],
    )
  })
}

resource "aws_iam_role" "collector_task" {
  name_prefix = "${var.name_prefix}-collector-task-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "collector_wal" {
  name = "wal-bucket"
  role = aws_iam_role.collector_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.wal_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.wal_bucket_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "collector_litellm_intake" {
  count = local.litellm_intake_enabled ? 1 : 0

  name = "litellm-intake"
  role = aws_iam_role.collector_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.litellm_intake_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:${local.partition}:s3:::${var.litellm_events_bucket}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "collector_codecommit_intake" {
  count = local.codecommit_intake_enabled ? 1 : 0

  name = "codecommit-intake"
  role = aws_iam_role.collector_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.codecommit_intake_queue_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "collector_publish" {
  name = "publish-enrich"
  role = aws_iam_role.collector_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = [var.enrich_topic_arn, var.work_enrich_topic_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "collector_store_apply" {
  name = "store-apply-send"
  role = aws_iam_role.collector_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
        Resource = var.store_apply_queue_arn
      }
    ]
  })
}
