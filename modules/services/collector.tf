# --- Collector: in-VPC telemetry ingest (ECS Fargate) ---

resource "aws_security_group" "collector" {
  name_prefix = "${var.name_prefix}-collector-"
  description = "TokenIQ collector service"
  vpc_id      = var.vpc_id

  # The ingress module (when enabled) adds NLB-facing rules to this SG by ID.
  ingress {
    description = "Collector HTTPS from inside the VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

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

resource "aws_cloudwatch_log_group" "collector" {
  name              = "/ecs/${var.name_prefix}-collector"
  retention_in_days = var.log_retention_days
}

locals {
  # Export to the hosted plane: only content-free metadata ever egresses.
  collector_export_environment = local.export_enabled ? [
    { name = "TOKENIQ_EXPORT_ENABLED", value = "true" },
    { name = "TOKENIQ_EXPORT_ENDPOINT", value = var.export_endpoint },
    { name = "TOKENIQ_EXPORT_TLS_ENABLED", value = "true" },
    { name = "TOKENIQ_EXPORT_IDENTITY_USER_MODE", value = var.export_identity_user_mode },
    { name = "TOKENIQ_EXPORT_IDENTITY_TEAM_MODE", value = var.export_identity_team_mode },
  ] : []

  collector_export_secrets = local.export_enabled ? [
    { name = "TOKENIQ_EXPORT_TENANT_KEY", valueFrom = var.export_tenant_key_secret_arn },
  ] : []

  collector_litellm_intake_environment = local.litellm_intake_enabled ? [
    { name = "TOKENIQ_PROXY_LITELLM_SQS_QUEUE_URL", value = var.litellm_intake_queue_url },
  ] : []

  collector_codecommit_intake_environment = local.codecommit_intake_enabled ? [
    { name = "TOKENIQ_GIT_CODECOMMIT_INTAKE_ENABLED", value = "true" },
    { name = "TOKENIQ_GIT_CODECOMMIT_SQS_QUEUE_URL", value = var.codecommit_intake_queue_url },
  ] : []

  # Outbound GitHub Events poller (App-authenticated backfill sweep).
  collector_poll_environment = var.git_github_backfill_enabled ? [
    { name = "TOKENIQ_GIT_GITHUB_APP_ID", value = var.git_github_app_id },
    { name = "TOKENIQ_GIT_POLL_INTERVAL", value = var.git_poll_interval },
  ] : []

  collector_poll_secrets = var.git_github_backfill_enabled ? [
    { name = "TOKENIQ_GIT_GITHUB_APP_PRIVATE_KEY", valueFrom = var.git_github_app_private_key_secret_arn },
  ] : []
}

resource "aws_ecs_task_definition" "collector" {
  family                   = "${var.name_prefix}-collector"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.collector_cpu
  memory                   = var.collector_memory
  execution_role_arn       = aws_iam_role.collector_execution.arn
  task_role_arn            = aws_iam_role.collector_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "collector"
      image     = var.collector_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = concat(
        [
          { name = "TOKENIQ_HTTP_ADDR", value = ":8080" },
          { name = "TOKENIQ_TENANT_ID", value = var.tenant_id },
          { name = "TOKENIQ_WAL_BUCKET", value = var.wal_bucket },
          { name = "TOKENIQ_WAL_PREFIX", value = "wal/" },
          { name = "TOKENIQ_ENRICH_TOPIC_ARN", value = var.enrich_topic_arn },
          { name = "TOKENIQ_WORK_ENRICH_TOPIC_ARN", value = var.work_enrich_topic_arn },
          { name = "TOKENIQ_GATEWAY_INGEST_ENABLED", value = "true" },
          { name = "TOKENIQ_KIRO_INGEST_ENABLED", value = "true" },
          { name = "TOKENIQ_AUTH_ENABLED", value = "true" },
          { name = "TOKENIQ_TLS_ENABLED", value = "true" },
          { name = "TOKENIQ_GIT_WEBHOOK_ENABLED", value = "true" },
          { name = "TOKENIQ_DDB_DUAL_WRITE", value = "false" },
          { name = "TOKENIQ_STORE_APPLY_QUEUE_URL", value = var.store_apply_queue_url },
          { name = "TOKENIQ_DATA_SERVICE_URL", value = var.data_service_url },
          # Empty disables pricing-at-ingest in the binary.
          { name = "TOKENIQ_PRICE_BOOK_URL", value = var.price_book_url },
        ],
        local.collector_export_environment,
        local.collector_litellm_intake_environment,
        local.collector_codecommit_intake_environment,
        local.collector_poll_environment,
      )

      secrets = concat(
        [
          { name = "TOKENIQ_GATEWAY_TENANT_KEY", valueFrom = var.gateway_tenant_key_secret_arn },
          { name = "TOKENIQ_KIRO_TENANT_KEY", valueFrom = var.kiro_tenant_key_secret_arn },
          { name = "TOKENIQ_GIT_GITHUB_WEBHOOK_SECRET", valueFrom = var.git_github_webhook_secret_arn },
          { name = "TOKENIQ_GIT_GITLAB_WEBHOOK_TOKEN", valueFrom = var.git_gitlab_webhook_token_secret_arn },
          { name = "TOKENIQ_AUTH_TOKEN", valueFrom = var.collector_auth_token_secret_arn },
          { name = "TOKENIQ_TLS_CERT_PEM", valueFrom = var.collector_tls_cert_secret_arn },
          { name = "TOKENIQ_TLS_KEY_PEM", valueFrom = var.collector_tls_key_secret_arn },
          { name = "TOKENIQ_DATA_SERVICE_AUTH_TOKEN", valueFrom = var.data_service_auth_token_secret_arn },
          { name = "TOKENIQ_DATA_SERVICE_TLS_CA_PEM", valueFrom = var.data_service_tls_cert_secret_arn },
        ],
        local.collector_export_secrets,
        local.collector_poll_secrets,
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.collector.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "collector"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "collector" {
  name            = "${var.name_prefix}-collector"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.collector.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.collector.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = var.collector_service_discovery_arn
  }

  dynamic "load_balancer" {
    for_each = var.collector_target_group_arn != "" ? [var.collector_target_group_arn] : []

    content {
      target_group_arn = load_balancer.value
      container_name   = "collector"
      container_port   = 8080
    }
  }

  health_check_grace_period_seconds = var.collector_target_group_arn == "" ? null : 60
}
