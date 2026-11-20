# TokenIQ Gateway — the optional inference data plane, deployed next to the
# collector so LLM request/response content never leaves the customer's AWS
# environment. The gateway is a stateless consumer of signed config bundles:
# it has no config-write API, verifies every bundle against the pinned
# public key, and keeps serving its last-applied config when the bundle
# source is unreachable (fail-static).
#
# Turn telemetry pushes to the collector over authenticated HTTP
# (TOKENIQ_TELEMETRY_MODE=http) using the same shared HMAC key the
# collector verifies with — the wiring the root module composes from
# modules/core. That path requires the collector endpoint to present a
# certificate the gateway trusts, i.e. ingress tls_mode = "acm" (the
# gateway's HTTP telemetry client has no custom-CA hook).

data "aws_region" "current" {}

locals {
  bundle_url = (
    var.bundle_url != "" ? var.bundle_url :
    # Tier 2 default: the module-owned bundle bucket, via the S3 REST
    # endpoint. Must be the REST endpoint (not s3-website): private-subnet
    # S3 traffic typically routes through the S3 Gateway VPC endpoint,
    # which serves the REST API only — s3-website requests 404 there.
    "https://${aws_s3_bucket.bundle[0].bucket}.s3.${data.aws_region.current.name}.amazonaws.com"
  )
}

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/ecs/${var.name_prefix}-gateway"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "gateway" {
  family                   = "${var.name_prefix}-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "gateway"
      image     = var.image
      essential = true

      portMappings = [
        { containerPort = 8080, protocol = "tcp" },
        {
          # Admin console + admin API, fronted by its own ALB target group
          # so /admin* reaches it without touching the data plane.
          containerPort = 8081
          protocol      = "tcp"
        }
      ]

      environment = concat([
        { name = "TOKENIQ_API_PORT", value = "8080" },
        { name = "TOKENIQ_METRICS_PORT", value = "9090" },
        { name = "TOKENIQ_TENANT_ID", value = var.tenant_id },
        { name = "TOKENIQ_BUNDLE_PUBLIC_KEY", value = var.bundle_public_key },
        {
          # Bundle-source base URL; the gateway appends
          # /v1/bundles/latest?after_version=N.
          name  = "TOKENIQ_BUNDLE_URL"
          value = local.bundle_url
        },
        { name = "TOKENIQ_BUNDLE_CACHE_PATH", value = "/tmp/bundle.signed.json" },
        {
          # Fresh tasks have no disk cache; hold boot briefly for the
          # first fetch so a deploy coinciding with a bundle-source blip
          # never puts a configless gateway into service. Keep below the
          # health-check grace period (60s).
          name  = "TOKENIQ_BUNDLE_BOOT_WAIT"
          value = var.bundle_boot_wait
        },
        {
          # Push each turn's telemetry envelope to the collector's
          # authenticated gateway-ingest endpoint. The collector verifies
          # the shared HMAC key injected below.
          name  = "TOKENIQ_TELEMETRY_MODE"
          value = "http"
        },
        { name = "TOKENIQ_TELEMETRY_HTTP_ENDPOINT", value = var.collector_endpoint },
        { name = "TOKENIQ_ADMIN_PORT", value = "8081" },
        {
          # The ALB matches /admin* but cannot strip the prefix, so the
          # console mounts itself there: assets resolve relative to the
          # base and the admin API lives under /admin/api/.
          name  = "TOKENIQ_ADMIN_BASE_PATH"
          value = "/admin"
        },
        {
          # http.Server sets the write deadline at request START, not at
          # first write, so a slow-but-successful upstream call fails
          # instantly when it finally responds. Must stay under the ALB
          # idle_timeout. Ladder, innermost out: upstream attempt <
          # write timeout < ALB idle. Keep the three in step when tuning.
          name  = "TOKENIQ_WRITE_TIMEOUT"
          value = var.write_timeout
        },
        {
          # Per-ATTEMPT upstream budget, not the whole call: the retry
          # loop gives each attempt a fresh one.
          name  = "TOKENIQ_UPSTREAM_TOTAL_TIMEOUT"
          value = var.upstream_total_timeout
        },
        ],
        var.bedrock_enabled ? [
          {
            # No API key: the Bedrock adapter resolves the AWS credential
            # chain, which in Fargate is the task role — the bedrock-invoke
            # policy in iam.tf IS the credential.
            name  = "TOKENIQ_BEDROCK_ENABLED"
            value = "true"
          },
          {
            # Set explicitly: the adapter refuses to construct with an
            # empty region, and ECS does not reliably export one.
            name  = "TOKENIQ_BEDROCK_REGION"
            value = data.aws_region.current.name
          },
        ] : [],
        local.redis_enabled ? [
          {
            # Bundled Redis (redis.tf): host:port of the replication
            # group's primary endpoint, which follows failover. Plaintext,
            # no AUTH (TGWY-248).
            name  = "TOKENIQ_REDIS_ADDR"
            value = local.redis_addr
          },
        ] : [],
        [for name, value in var.extra_environment : { name = name, value = value }],
      )

      secrets = concat([
        {
          # Shared HMAC; must equal the collector's
          # TOKENIQ_GATEWAY_TENANT_KEY (modules/core provisions one secret
          # both services read, so the values agree).
          name      = "TOKENIQ_TELEMETRY_HTTP_TENANT_KEY"
          valueFrom = var.telemetry_tenant_key_secret_arn
        },
        {
          # Bearer for the admin API. The console prompts for it;
          # operators read the value out of Secrets Manager.
          name      = "TOKENIQ_ADMIN_TOKEN"
          valueFrom = aws_secretsmanager_secret.admin_token.arn
        },
        ],
        var.bundle_tenant_key_secret_arn != "" ? [
          {
            # Tier 3 bundle-poll Bearer: presented verbatim to the hosted
            # config-distributor. Only wire this together with a
            # distributor bundle_url — S3 400s on a Bearer Authorization
            # header, failing every poll.
            name      = "TOKENIQ_BUNDLE_TENANT_KEY"
            valueFrom = var.bundle_tenant_key_secret_arn
          },
        ] : [],
        [for name, arn in var.extra_secrets : { name = name, valueFrom = arn }],
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.gateway.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "gateway"
        }
      }

      # No container-level healthCheck: the image is distroless
      # (gcr.io/distroless/static-debian12) with no shell, so any
      # CMD-SHELL probe fails and crash-loops the task. Liveness is
      # governed by the ALB target-group health check (GET /healthz).
    }
  ])
}

resource "aws_ecs_service" "gateway" {
  name                              = "${var.name_prefix}-gateway"
  cluster                           = var.cluster_arn
  task_definition                   = aws_ecs_task_definition.gateway.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "gateway"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.admin.arn
    container_name   = "gateway"
    container_port   = 8081
  }
}
