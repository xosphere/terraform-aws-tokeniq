locals {
  version               = var.tokeniq_version
  release_bucket_prefix = "xosphere-io-releases-"
  lambda_s3_bucket      = "${local.release_bucket_prefix}${data.aws_region.current.name}"
  lambda_s3_key         = "tokeniq/ingest-lambda-${local.version}.zip"
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
        Sid    = "DLQSend"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.ingest_dlq.arn
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
