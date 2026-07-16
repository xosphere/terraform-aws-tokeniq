# --- LiteLLM landing-zone EventBridge intake ---
# The customer's LiteLLM bucket emits S3 "Object Created" events on the default
# event bus (once the customer enables EventBridge on the bucket). This rule
# matches those events for litellm_events_bucket and routes them to the intake
# SQS queue, which the collector long-polls and ingests via its litellm_s3
# adapter. The collector parses the native EventBridge envelope directly, so no
# input transformer is needed. This module owns the rule + queue; it never owns
# or modifies the customer's bucket.

locals {
  # EventBridge content filter: match this bucket, and — when a prefix is set —
  # only keys under that prefix, so a shared bucket only feeds LiteLLM objects.
  litellm_event_detail = merge(
    { bucket = { name = [var.litellm_events_bucket] } },
    var.litellm_events_prefix != "" ? {
      object = { key = [{ prefix = var.litellm_events_prefix }] }
    } : {},
  )
}

resource "aws_cloudwatch_event_rule" "litellm_object_created" {
  name        = "${var.name_prefix}-litellm-object-created"
  description = "Route LiteLLM raw-events bucket Object Created events to the collector intake queue."

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail        = local.litellm_event_detail
  })
}

resource "aws_cloudwatch_event_target" "litellm_ingest" {
  rule = aws_cloudwatch_event_rule.litellm_object_created.name
  arn  = aws_sqs_queue.litellm_ingest.arn
}

resource "aws_sqs_queue" "litellm_ingest_dlq" {
  name                      = "${var.name_prefix}-litellm-ingest-dlq"
  message_retention_seconds = 1209600 # 14 days — poison events stay inspectable.
}

resource "aws_sqs_queue" "litellm_ingest" {
  name = "${var.name_prefix}-litellm-ingest"
  # Fetching + ingesting one S3 object is quick, but give a slow turn room before
  # redelivery; downstream ingest is idempotent by turn_id, so redelivery is safe.
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.litellm_ingest_dlq.arn
    maxReceiveCount     = 5
  })
}

# Allow ONLY the EventBridge rule to enqueue onto the intake queue.
resource "aws_sqs_queue_policy" "litellm_ingest" {
  queue_url = aws_sqs_queue.litellm_ingest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.litellm_ingest.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.litellm_object_created.arn }
        }
      }
    ]
  })
}
