# ---- Dashboard API Lambda (conditional) ----

resource "aws_lambda_function" "dashboard_api" {
  count         = var.grafana_enabled ? 1 : 0
  function_name = "xosphere-tokeniq-dashboard-api"
  role          = aws_iam_role.dashboard_api_lambda[0].arn
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
      DYNAMODB_COMMIT_ATTR_TABLE_NAME  = aws_dynamodb_table.commit_attributions.name
      DYNAMODB_COMMIT_INDEX_TABLE_NAME = aws_dynamodb_table.commit_index.name
      TOKENIQ_VERSION                  = local.version
    }
  }
}

resource "aws_cloudwatch_log_group" "dashboard_api" {
  count             = var.grafana_enabled ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.dashboard_api[0].function_name}"
  retention_in_days = 30
}

resource "aws_iam_role" "dashboard_api_lambda" {
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

resource "aws_iam_role_policy" "dashboard_api_lambda" {
  count = var.grafana_enabled ? 1 : 0
  name  = "xosphere-tokeniq-dashboard-api-policy"
  role  = aws_iam_role.dashboard_api_lambda[0].id

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
          "${aws_dynamodb_table.commit_attributions.arn}/index/*"
        ]
      }
    ]
  })
}

# ---- API Gateway v2 (HTTP API) ----

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

resource "aws_apigatewayv2_route" "query" {
  count     = var.grafana_enabled ? 1 : 0
  api_id    = aws_apigatewayv2_api.dashboard[0].id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard[0].id}"
}

resource "aws_apigatewayv2_route" "health" {
  count     = var.grafana_enabled ? 1 : 0
  api_id    = aws_apigatewayv2_api.dashboard[0].id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.dashboard[0].id}"
}

resource "aws_lambda_permission" "dashboard_api_gw" {
  count         = var.grafana_enabled ? 1 : 0
  function_name = aws_lambda_function.dashboard_api[0].function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dashboard[0].execution_arn}/*"
}

# ---- Amazon Managed Grafana Workspace (conditional) ----

resource "aws_grafana_workspace" "tokeniq" {
  count                    = var.grafana_enabled ? 1 : 0
  name                     = "xosphere-tokeniq"
  description              = "TokenIQ - AI Usage Intelligence Dashboard"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = [var.grafana_auth_provider]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_workspace[0].arn
  data_sources             = ["CLOUDWATCH"]
  grafana_version          = "10.4"
}

resource "aws_iam_role" "grafana_workspace" {
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

resource "aws_iam_role_policy" "grafana_workspace" {
  count = var.grafana_enabled ? 1 : 0
  name  = "xosphere-tokeniq-grafana-policy"
  role  = aws_iam_role.grafana_workspace[0].id

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
