locals {
  version               = var.version
  release_bucket_prefix = "xosphere-io-releases-"
  lambda_s3_bucket      = "${local.release_bucket_prefix}${data.aws_region.current.name}"
  lambda_s3_key         = "tokeniq/ingest-lambda-${local.version}.zip"
  has_anthropic_key     = var.anthropic_api_key != ""
  plan_queue_url        = local.has_anthropic_key ? aws_sqs_queue.plan_analysis[0].url : ""
  plan_analyzer_has_vpc = length(var.plan_analyzer_vpc_subnet_ids) > 0
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---- S3: Raw Turn Landing Zone ----

resource "aws_s3_bucket" "turns_raw" {
  bucket        = "xosphere-tokeniq-events-raw-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "turns_raw" {
  bucket = aws_s3_bucket.turns_raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "turns_raw" {
  bucket = aws_s3_bucket.turns_raw.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "expiration"
    status = "Enabled"

    expiration {
      days = var.retention_days
    }
  }
}

resource "aws_s3_bucket_notification" "turns_raw" {
  bucket = aws_s3_bucket.turns_raw.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# ---- SQS: Dead Letter Queue for Lambda Failures ----

resource "aws_sqs_queue" "ingest_dlq" {
  name                      = "xosphere-tokeniq-ingest-dlq"
  message_retention_seconds = 1209600 # 14 days
}

# ---- Lambda: Ingest Processor ----

resource "aws_lambda_function" "ingest" {
  function_name = "xosphere-tokeniq-ingest"
  role          = aws_iam_role.ingest_lambda.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  s3_bucket = local.lambda_s3_bucket
  s3_key    = local.lambda_s3_key

  environment {
    variables = {
      DYNAMODB_TABLE_NAME              = aws_dynamodb_table.turns.name
      DYNAMODB_SESSIONS_TABLE_NAME     = aws_dynamodb_table.sessions.name
      DYNAMODB_COMMIT_INDEX_TABLE_NAME = aws_dynamodb_table.commit_index.name
      DYNAMODB_COMMIT_ATTR_TABLE_NAME  = aws_dynamodb_table.commit_attributions.name
      DYNAMODB_PLAN_ATTR_TABLE_NAME    = aws_dynamodb_table.plan_attributions.name
      SQS_PLAN_ANALYSIS_QUEUE_URL      = local.plan_queue_url
      TOKENIQ_VERSION                  = local.version
    }
  }
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ingest.function_name
  principal      = "s3.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_lambda_function_event_invoke_config" "ingest" {
  function_name          = aws_lambda_function.ingest.function_name
  maximum_retry_attempts = 2

  destination_config {
    on_failure {
      destination = aws_sqs_queue.ingest_dlq.arn
    }
  }
}

resource "aws_cloudwatch_log_group" "ingest_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 30
}

# ---- IAM: Lambda Execution Role ----

resource "aws_iam_role" "ingest_lambda" {
  name = "xosphere-tokeniq-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ingest_lambda" {
  name = "xosphere-tokeniq-ingest-policy"
  role = aws_iam_role.ingest_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/xosphere-tokeniq-*"
      },
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.turns_raw.arn}/*"
      },
      {
        Sid    = "DynamoDBTurnsWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.turns.arn,
          "${aws_dynamodb_table.turns.arn}/index/*"
        ]
      },
      {
        Sid    = "DynamoDBSessionsReadWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.sessions.arn
      },
      {
        Sid    = "DynamoDBCommitIndex"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.commit_index.arn
      },
      {
        Sid    = "DynamoDBCommitAttributions"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.commit_attributions.arn,
          "${aws_dynamodb_table.commit_attributions.arn}/index/*"
        ]
      },
      {
        Sid    = "DynamoDBPlanAttributions"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.plan_attributions.arn,
          "${aws_dynamodb_table.plan_attributions.arn}/index/*"
        ]
      },
      {
        Sid    = "DLQSend"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.ingest_dlq.arn
      },
      {
        Sid    = "PlanAnalysisQueueSend"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:xosphere-tokeniq-plan-analysis"
      }
    ]
  })
}

# ---- DynamoDB: Turns Table ----

resource "aws_dynamodb_table" "turns" {
  name         = "xosphere-tokeniq-turns"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "turn_id"

  attribute {
    name = "turn_id"
    type = "S"
  }

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name            = "session_id-timestamp-index"
    hash_key        = "session_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "user_id-timestamp-index"
    hash_key        = "user_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ---- DynamoDB: Sessions Table ----

resource "aws_dynamodb_table" "sessions" {
  name         = "xosphere-tokeniq-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ---- DynamoDB: Commit Index Table ----

resource "aws_dynamodb_table" "commit_index" {
  name         = "xosphere-tokeniq-commit-index"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "commit_sha"

  attribute {
    name = "commit_sha"
    type = "S"
  }
}

# ---- DynamoDB: Commit Attributions Table ----

resource "aws_dynamodb_table" "commit_attributions" {
  name         = "xosphere-tokeniq-commit-attributions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "short_sha"

  attribute {
    name = "short_sha"
    type = "S"
  }

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "end_time"
    type = "S"
  }

  global_secondary_index {
    name            = "session_id-end_time-index"
    hash_key        = "session_id"
    range_key       = "end_time"
    projection_type = "ALL"
  }
}

# ---- DynamoDB: Plan Attributions Table ----

resource "aws_dynamodb_table" "plan_attributions" {
  name         = "xosphere-tokeniq-plan-attributions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "plan_id"

  attribute {
    name = "plan_id"
    type = "S"
  }

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "extracted_at"
    type = "S"
  }

  attribute {
    name = "analysis_status"
    type = "S"
  }

  global_secondary_index {
    name            = "session_id-extracted_at-index"
    hash_key        = "session_id"
    range_key       = "extracted_at"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "analysis_status-extracted_at-index"
    hash_key        = "analysis_status"
    range_key       = "extracted_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ---- Plan Analysis Infrastructure (conditional on anthropic_api_key) ----

resource "aws_secretsmanager_secret" "anthropic_api_key" {
  count       = local.has_anthropic_key ? 1 : 0
  name        = "xosphere-tokeniq-anthropic-api-key"
  description = "Anthropic API key for TokenIQ plan time estimation"
}

resource "aws_secretsmanager_secret_version" "anthropic_api_key" {
  count         = local.has_anthropic_key ? 1 : 0
  secret_id     = aws_secretsmanager_secret.anthropic_api_key[0].id
  secret_string = jsonencode({ api_key = var.anthropic_api_key })
}

resource "aws_sqs_queue" "plan_analysis_dlq" {
  count                     = local.has_anthropic_key ? 1 : 0
  name                      = "xosphere-tokeniq-plan-analysis-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "plan_analysis" {
  count                      = local.has_anthropic_key ? 1 : 0
  name                       = "xosphere-tokeniq-plan-analysis"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.plan_analysis_dlq[0].arn
    maxReceiveCount     = 3
  })
}

resource "aws_lambda_function" "plan_analyzer" {
  count         = local.has_anthropic_key ? 1 : 0
  function_name = "xosphere-tokeniq-plan-analyzer"
  role          = aws_iam_role.plan_analyzer[0].arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  memory_size   = 256
  timeout       = 120

  s3_bucket = local.lambda_s3_bucket
  s3_key    = "tokeniq/plan-analyzer-lambda-${local.version}.zip"

  environment {
    variables = {
      DYNAMODB_PLAN_ATTR_TABLE_NAME = aws_dynamodb_table.plan_attributions.name
      DYNAMODB_SESSIONS_TABLE_NAME  = aws_dynamodb_table.sessions.name
      ANTHROPIC_API_KEY_SECRET_ID   = aws_secretsmanager_secret.anthropic_api_key[0].id
      ANTHROPIC_API_URL             = var.anthropic_api_url
      TOKENIQ_VERSION               = local.version
    }
  }

  dynamic "vpc_config" {
    for_each = local.plan_analyzer_has_vpc ? [1] : []
    content {
      subnet_ids         = var.plan_analyzer_vpc_subnet_ids
      security_group_ids = var.plan_analyzer_vpc_security_group_ids
    }
  }
}

resource "aws_lambda_event_source_mapping" "plan_analyzer" {
  count                   = local.has_anthropic_key ? 1 : 0
  event_source_arn        = aws_sqs_queue.plan_analysis[0].arn
  function_name           = aws_lambda_function.plan_analyzer[0].arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_cloudwatch_log_group" "plan_analyzer" {
  count             = local.has_anthropic_key ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.plan_analyzer[0].function_name}"
  retention_in_days = 30
}

resource "aws_iam_role" "plan_analyzer" {
  count = local.has_anthropic_key ? 1 : 0
  name  = "xosphere-tokeniq-plan-analyzer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "plan_analyzer" {
  count = local.has_anthropic_key ? 1 : 0
  name  = "xosphere-tokeniq-plan-analyzer-policy"
  role  = aws_iam_role.plan_analyzer[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/xosphere-tokeniq-*"
      },
      {
        Sid      = "SQSConsume"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.plan_analysis[0].arn
      },
      {
        Sid      = "DynamoDBPlanReadWrite"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.plan_attributions.arn
      },
      {
        Sid      = "DynamoDBSessionsUpdate"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.sessions.arn
      },
      {
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.anthropic_api_key[0].arn
      },
      {
        Sid    = "VpcNetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---- Grafana Dashboard Infrastructure (conditional) ----

resource "aws_lambda_function" "dashboard_api" {
  count         = var.grafana_enabled ? 1 : 0
  function_name = "xosphere-tokeniq-dashboard-api"
  role          = aws_iam_role.dashboard_api[0].arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  memory_size   = 256
  timeout       = 30

  s3_bucket = local.lambda_s3_bucket
  s3_key    = "tokeniq/dashboard-api-lambda-${local.version}.zip"

  environment {
    variables = {
      DYNAMODB_TABLE_NAME              = aws_dynamodb_table.turns.name
      DYNAMODB_SESSIONS_TABLE_NAME     = aws_dynamodb_table.sessions.name
      DYNAMODB_COMMIT_INDEX_TABLE_NAME = aws_dynamodb_table.commit_index.name
      DYNAMODB_COMMIT_ATTR_TABLE_NAME  = aws_dynamodb_table.commit_attributions.name
      DYNAMODB_PLAN_ATTR_TABLE_NAME    = aws_dynamodb_table.plan_attributions.name
      TOKENIQ_VERSION                  = local.version
    }
  }
}

resource "aws_cloudwatch_log_group" "dashboard_api" {
  count             = var.grafana_enabled ? 1 : 0
  name              = "/aws/lambda/xosphere-tokeniq-dashboard-api"
  retention_in_days = 30
}

resource "aws_iam_role" "dashboard_api" {
  count = var.grafana_enabled ? 1 : 0
  name  = "xosphere-tokeniq-dashboard-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dashboard_api" {
  count = var.grafana_enabled ? 1 : 0
  name  = "xosphere-tokeniq-dashboard-api-policy"
  role  = aws_iam_role.dashboard_api[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/xosphere-tokeniq-*"
      },
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.turns.arn,
          "${aws_dynamodb_table.turns.arn}/index/*",
          aws_dynamodb_table.sessions.arn,
          aws_dynamodb_table.commit_attributions.arn,
          "${aws_dynamodb_table.commit_attributions.arn}/index/*",
          aws_dynamodb_table.plan_attributions.arn,
          "${aws_dynamodb_table.plan_attributions.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_apigatewayv2_api" "dashboard" {
  count         = var.grafana_enabled ? 1 : 0
  name          = "xosphere-tokeniq-dashboard-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }
}

resource "aws_apigatewayv2_stage" "dashboard" {
  count       = var.grafana_enabled ? 1 : 0
  api_id      = aws_apigatewayv2_api.dashboard[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "dashboard" {
  count                  = var.grafana_enabled ? 1 : 0
  api_id                 = aws_apigatewayv2_api.dashboard[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dashboard_api[0].arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "dashboard_query" {
  count     = var.grafana_enabled ? 1 : 0
  api_id    = aws_apigatewayv2_api.dashboard[0].id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard[0].id}"
}

resource "aws_apigatewayv2_route" "dashboard_health" {
  count     = var.grafana_enabled ? 1 : 0
  api_id    = aws_apigatewayv2_api.dashboard[0].id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard[0].id}"
}

resource "aws_lambda_permission" "dashboard_api_gw" {
  count         = var.grafana_enabled ? 1 : 0
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dashboard[0].execution_arn}/*"
}

resource "aws_grafana_workspace" "tokeniq" {
  count                    = var.grafana_enabled ? 1 : 0
  name                     = "xosphere-tokeniq"
  description              = "TokenIQ - AI Usage Intelligence Dashboard"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = [var.grafana_auth_provider]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["CLOUDWATCH"]
  grafana_version          = "10.4"
}

resource "aws_iam_role" "grafana" {
  count = var.grafana_enabled ? 1 : 0
  name  = "xosphere-tokeniq-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "grafana" {
  count = var.grafana_enabled ? 1 : 0
  name  = "xosphere-tokeniq-grafana-policy"
  role  = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/xosphere-tokeniq-*"
      }
    ]
  })
}
