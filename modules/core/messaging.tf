# --- Enrichment fan-out topology ---
# The collector publishes one "enrich" event per turn to an SNS topic; each
# enricher owns its own SQS queue subscribed to that topic, so enrichment
# compute (including LLM calls) scales out per consumer. Enrichers do NOT
# write the local SQLite store directly — they publish results to a single
# store-apply queue drained by the lone store-writer, which structurally
# removes multi-writer contention on the WAL file.

locals {
  # One SQS queue per enricher, each its own SNS subscription. Adding an
  # enricher is a one-line edit here.
  enrichers = toset(["attribution", "plan", "pattern", "session-index"])

  # At-least-once SQS delivery is fine: the store-writer upserts are
  # idempotent (event_version dedup), so a redelivered message is a no-op.
  max_receive_count = 5
}

# --- SNS "enrich" topic ---
resource "aws_sns_topic" "enrich" {
  name = "${var.name_prefix}-enrich"
}

# --- Per-enricher SQS queues + DLQs ---
resource "aws_sqs_queue" "enricher_dlq" {
  for_each = local.enrichers

  name                      = "${var.name_prefix}-enrich-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days — max, so poison messages are inspectable.
}

resource "aws_sqs_queue" "enricher" {
  for_each = local.enrichers

  name = "${var.name_prefix}-enrich-${each.key}"
  # Enrichment may call an LLM; give a slow turn room to finish before redelivery.
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.enricher_dlq[each.key].arn
    maxReceiveCount     = local.max_receive_count
  })
}

# Raw delivery hands the consumer the collector's JSON body verbatim (no SNS
# envelope to unwrap).
resource "aws_sns_topic_subscription" "enricher" {
  for_each = local.enrichers

  topic_arn            = aws_sns_topic.enrich.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.enricher[each.key].arn
  raw_message_delivery = true
}

# Allow ONLY this SNS topic to enqueue onto each enricher queue.
resource "aws_sqs_queue_policy" "enricher" {
  for_each = local.enrichers

  queue_url = aws_sqs_queue.enricher[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.enricher[each.key].arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.enrich.arn }
        }
      }
    ]
  })
}

# --- store-apply queue + DLQ ---
# Enrichers publish their upsert batches here; the single store-writer drains
# it and owns the SQLite file. Not fed by SNS — enrichers send directly.
resource "aws_sqs_queue" "store_apply_dlq" {
  name                      = "${var.name_prefix}-store-apply-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "store_apply" {
  name = "${var.name_prefix}-store-apply"
  # Batched idempotent upserts complete quickly; a redelivered batch is a no-op.
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.store_apply_dlq.arn
    maxReceiveCount     = local.max_receive_count
  })
}

# --- SNS "work-enrich" topic + pattern work queue ---
# The collector's git-webhook ingest and the enricher's git backfill both
# publish content-free WorkEvents (commit attributions) to this topic; it fans
# out to the pattern engine's work queue, which the enricher's WorkSQSRunner
# long-polls.
resource "aws_sns_topic" "work_enrich" {
  name = "${var.name_prefix}-work-enrich"
}

resource "aws_sqs_queue" "work_dlq" {
  name                      = "${var.name_prefix}-work-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "work" {
  name = "${var.name_prefix}-work"
  # Hydration/attribution per WorkEvent is quick; a redelivered event collapses
  # downstream by commit identity, so at-least-once is a no-op.
  visibility_timeout_seconds = 120
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.work_dlq.arn
    maxReceiveCount     = local.max_receive_count
  })
}

resource "aws_sns_topic_subscription" "work" {
  topic_arn            = aws_sns_topic.work_enrich.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.work.arn
  raw_message_delivery = true
}

resource "aws_sqs_queue_policy" "work" {
  queue_url = aws_sqs_queue.work.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.work.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.work_enrich.arn }
        }
      }
    ]
  })
}
