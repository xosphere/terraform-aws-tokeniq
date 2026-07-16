# --- Enricher: one Fargate task running all enrichers (ECS Fargate) ---

resource "aws_security_group" "enricher" {
  name_prefix = "${var.name_prefix}-enricher-"
  description = "TokenIQ enricher service (egress only)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "enricher" {
  name              = "/ecs/${var.name_prefix}-enricher"
  retention_in_days = var.log_retention_days
}

locals {
  enricher_export_environment = local.export_enabled ? [
    { name = "TOKENIQ_EXPORT_ENABLED", value = "true" },
    { name = "TOKENIQ_EXPORT_ENDPOINT", value = var.export_endpoint },
    { name = "TOKENIQ_EXPORT_TLS_ENABLED", value = "true" },
  ] : []

  enricher_export_secrets = local.export_enabled ? [
    { name = "TOKENIQ_EXPORT_TENANT_KEY", valueFrom = var.export_tenant_key_secret_arn },
  ] : []

  enricher_backfill_environment = concat(
    local.git_backfill_enabled ? [
      { name = "TOKENIQ_GIT_BACKFILL_ENABLED", value = "true" },
      { name = "TOKENIQ_WORK_ENRICH_TOPIC_ARN", value = var.work_enrich_topic_arn },
    ] : [],
    var.git_github_backfill_enabled ? [
      { name = "TOKENIQ_GIT_GITHUB_APP_ID", value = var.git_github_app_id },
    ] : [],
    var.git_codecommit_backfill_enabled ? [
      { name = "TOKENIQ_GIT_CODECOMMIT_ENABLED", value = "true" },
    ] : [],
    var.git_codecommit_backfill_enabled && var.codecommit_read_role_arn != "" ? [
      { name = "TOKENIQ_GIT_CODECOMMIT_READ_ROLE_ARN", value = var.codecommit_read_role_arn },
    ] : [],
  )

  enricher_backfill_secrets = concat(
    var.git_github_backfill_enabled ? [
      { name = "TOKENIQ_GIT_GITHUB_APP_PRIVATE_KEY", valueFrom = var.git_github_app_private_key_secret_arn },
    ] : [],
    var.git_gitlab_backfill_enabled ? [
      { name = "TOKENIQ_GIT_GITLAB_TOKEN", valueFrom = var.git_gitlab_backfill_token_secret_arn },
    ] : [],
  )

  enricher_backfill_secret_arns = concat(
    var.git_github_backfill_enabled ? [var.git_github_app_private_key_secret_arn] : [],
    var.git_gitlab_backfill_enabled ? [var.git_gitlab_backfill_token_secret_arn] : [],
  )

  enricher_analyzer_environment = var.session_analyzer_enabled ? [
    { name = "TOKENIQ_SESSION_ANALYZER_LLM_ENDPOINT", value = var.session_analyzer_llm_endpoint },
    { name = "TOKENIQ_SESSION_ANALYZER_LLM_MODEL", value = var.session_analyzer_llm_model },
    { name = "TOKENIQ_SESSION_ANALYZER_LLM_MODE", value = "batch" },
    { name = "TOKENIQ_WAL_BUCKET", value = var.wal_bucket },
  ] : []

  enricher_analyzer_secrets = var.session_analyzer_enabled ? [
    { name = "TOKENIQ_SESSION_ANALYZER_LLM_API_KEY", valueFrom = var.session_analyzer_llm_api_key_secret_arn },
  ] : []
}

# --- Enricher execution role ---

resource "aws_iam_role" "enricher_execution" {
  name_prefix = "${var.name_prefix}-enricher-exec-"

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

resource "aws_iam_role_policy_attachment" "enricher_execution" {
  role       = aws_iam_role.enricher_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "enricher_execution_export_secrets" {
  count = local.export_enabled ? 1 : 0

  name = "export-secrets-read"
  role = aws_iam_role.enricher_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.export_tenant_key_secret_arn
      },
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
    ]
  })
}

resource "aws_iam_role_policy" "enricher_execution_data_service_secrets" {
  name = "data-service-secrets-read"
  role = aws_iam_role.enricher_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          var.data_service_auth_token_secret_arn,
          var.data_service_tls_cert_secret_arn,
        ]
      },
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
    ]
  })
}

resource "aws_iam_role_policy" "enricher_execution_backfill_secrets" {
  count = length(local.enricher_backfill_secret_arns) > 0 ? 1 : 0

  name = "backfill-secrets-read"
  role = aws_iam_role.enricher_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = local.enricher_backfill_secret_arns
      },
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
    ]
  })
}

resource "aws_iam_role_policy" "enricher_execution_analyzer_secrets" {
  count = var.session_analyzer_enabled ? 1 : 0

  name = "analyzer-secrets-read"
  role = aws_iam_role.enricher_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.session_analyzer_llm_api_key_secret_arn
      },
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
    ]
  })
}

# --- Enricher task role ---

resource "aws_iam_role" "enricher_task" {
  name_prefix = "${var.name_prefix}-enricher-task-"

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

resource "aws_iam_role_policy" "enricher_queues" {
  name = "queues-and-wal"
  role = aws_iam_role.enricher_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
        Resource = concat(values(var.enricher_queue_arns), [var.work_queue_arn])
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
        Resource = var.store_apply_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
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

resource "aws_iam_role_policy" "enricher_analysis_cache" {
  count = var.session_analyzer_enabled ? 1 : 0

  name = "analysis-cache-write"
  role = aws_iam_role.enricher_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${var.wal_bucket_arn}/analysis-cache/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "enricher_backfill_publish" {
  count = local.git_backfill_enabled ? 1 : 0

  name = "backfill-publish"
  role = aws_iam_role.enricher_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.work_enrich_topic_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "enricher_codecommit_read" {
  count = var.git_codecommit_backfill_enabled && length(var.codecommit_repos) > 0 ? 1 : 0

  name = "codecommit-read"
  role = aws_iam_role.enricher_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codecommit:GetDifferences",
          "codecommit:GetCommit",
          "codecommit:BatchGetCommits",
          "codecommit:GetBranch",
          "codecommit:GetRepository",
          "codecommit:GetBlob",
        ]
        Resource = [
          for repo in var.codecommit_repos :
          "arn:${local.partition}:codecommit:${local.region}:${local.codecommit_account}:${repo}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "enricher_codecommit_assume" {
  count = var.git_codecommit_backfill_enabled && var.codecommit_read_role_arn != "" ? 1 : 0

  name = "codecommit-assume"
  role = aws_iam_role.enricher_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = var.codecommit_read_role_arn
      }
    ]
  })
}

# --- Enricher task definition + service ---

resource "aws_ecs_task_definition" "enricher" {
  family                   = "${var.name_prefix}-enricher"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.enricher_cpu
  memory                   = var.enricher_memory
  execution_role_arn       = aws_iam_role.enricher_execution.arn
  task_role_arn            = aws_iam_role.enricher_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "enricher"
      image     = var.enricher_image
      essential = true

      environment = concat(
        [
          # ~90% of task memory: without it Go's GC lets RSS reach 2x live
          # heap and Fargate OOM-kills the task (exit 137).
          { name = "GOMEMLIMIT", value = "${floor(var.enricher_memory * 0.9)}MiB" },
          { name = "TOKENIQ_TENANT_ID", value = var.tenant_id },
          { name = "TOKENIQ_ENRICH_ATTRIBUTION_QUEUE", value = var.enricher_queue_urls["attribution"] },
          { name = "TOKENIQ_ENRICH_PATTERN_QUEUE", value = var.enricher_queue_urls["pattern"] },
          { name = "TOKENIQ_ENRICH_WORK_QUEUE", value = var.work_queue_url },
          { name = "TOKENIQ_PATTERN_ENGINE_ENABLED", value = "true" },
          { name = "TOKENIQ_SESSION_INDEX_ENABLED", value = "true" },
          { name = "TOKENIQ_ENRICH_SESSION_INDEX_QUEUE", value = var.enricher_queue_urls["session-index"] },
          { name = "TOKENIQ_DATA_SERVICE_URL", value = var.data_service_url },
          { name = "TOKENIQ_STORE_APPLY_QUEUE", value = var.store_apply_queue_url },
        ],
        local.enricher_export_environment,
        local.enricher_backfill_environment,
        local.enricher_analyzer_environment,
      )

      secrets = concat(
        [
          { name = "TOKENIQ_DATA_SERVICE_AUTH_TOKEN", valueFrom = var.data_service_auth_token_secret_arn },
          { name = "TOKENIQ_DATA_SERVICE_TLS_CA_PEM", valueFrom = var.data_service_tls_cert_secret_arn },
        ],
        local.enricher_export_secrets,
        local.enricher_backfill_secrets,
        local.enricher_analyzer_secrets,
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.enricher.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "enricher"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "enricher" {
  name            = "${var.name_prefix}-enricher"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.enricher.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.enricher.id]
    assign_public_ip = false
  }
}
