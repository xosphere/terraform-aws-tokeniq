# --- CodeCommit live-intake EventBridge rule + queue ---
# CodeCommit emits "CodeCommit Repository State Change" events on the default
# in-account event bus. The rule matches branch pushes (referenceUpdated /
# referenceCreated on a branch ref) for the tracked repos and routes them to
# the intake SQS queue, which the collector's GitEventPoller long-polls,
# recording one git_pushes row per push straight from the event (before + after
# are in the event, so no CodeCommit read on the collector). referenceDeleted
# and tag refs are excluded at the pattern so they never reach the queue. This
# is CodeCommit's egress-free live path — no inbound webhook, no provider poll.

data "aws_partition" "current" {}

locals {
  cross_account = var.codecommit_account_id != ""
}

# Cross-account intake bus (only when the repos live in another account). The
# repo account emits "CodeCommit Repository State Change" events on ITS OWN
# default bus and cannot deliver cross-account to a foreign default bus, so it
# must forward them (a producer rule the customer creates in the repo account)
# onto this custom bus, which the intake rule below listens on instead of the
# local default bus. Same-account topology never creates this.
resource "aws_cloudwatch_event_bus" "codecommit_xacct" {
  count = local.cross_account ? 1 : 0
  name  = "${var.name_prefix}-codecommit"
}

# Allow ONLY the repo account to PutEvents onto the custom bus. Scoped to the
# whole account (the forward rule's EventBridge-assumed role lives there); the
# rule's own pattern still filters to source=aws.codecommit + the tracked
# repos, so a stray PutEvents from that account matches nothing downstream.
resource "aws_cloudwatch_event_bus_policy" "codecommit_xacct" {
  count          = local.cross_account ? 1 : 0
  event_bus_name = aws_cloudwatch_event_bus.codecommit_xacct[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowRepoAccountPutEvents"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${var.codecommit_account_id}:root" }
        Action    = "events:PutEvents"
        Resource  = aws_cloudwatch_event_bus.codecommit_xacct[0].arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "codecommit_state_change" {
  name        = "${var.name_prefix}-codecommit-state-change"
  description = "Route CodeCommit branch push (referenceUpdated/referenceCreated) events for the tracked repos to the collector CodeCommit intake queue."

  # Cross-account: listen on the custom bus the repo account forwards onto.
  # Same-account: null ⇒ the local default bus, where CodeCommit emits natively.
  # Forwarded events keep source/detail-type/detail intact, so the pattern
  # below matches identically on either bus.
  event_bus_name = local.cross_account ? aws_cloudwatch_event_bus.codecommit_xacct[0].name : null

  event_pattern = jsonencode({
    source        = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    detail = {
      repositoryName = var.codecommit_repos
      event          = ["referenceUpdated", "referenceCreated"]
      referenceType  = ["branch"]
    }
  })
}

resource "aws_cloudwatch_event_target" "codecommit_ingest" {
  rule = aws_cloudwatch_event_rule.codecommit_state_change.name
  # Must name the same bus the rule lives on (null ⇒ default bus, same-account).
  event_bus_name = local.cross_account ? aws_cloudwatch_event_bus.codecommit_xacct[0].name : null
  arn            = aws_sqs_queue.codecommit_ingest.arn
}

resource "aws_sqs_queue" "codecommit_ingest_dlq" {
  name                      = "${var.name_prefix}-codecommit-ingest-dlq"
  message_retention_seconds = 1209600 # 14 days — poison events stay inspectable.
}

resource "aws_sqs_queue" "codecommit_ingest" {
  name = "${var.name_prefix}-codecommit-ingest"
  # Recording a git_pushes row from the event is quick; give room before
  # redelivery. The git_pushes upsert is idempotent by provider+repo+after_sha,
  # so at-least-once delivery is a no-op.
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.codecommit_ingest_dlq.arn
    maxReceiveCount     = 5
  })
}

# Allow ONLY the EventBridge rule to enqueue onto the intake queue.
resource "aws_sqs_queue_policy" "codecommit_ingest" {
  queue_url = aws_sqs_queue.codecommit_ingest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.codecommit_ingest.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.codecommit_state_change.arn }
        }
      }
    ]
  })
}
