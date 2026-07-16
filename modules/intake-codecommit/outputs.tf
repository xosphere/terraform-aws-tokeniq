output "queue_url" {
  description = "CodeCommit intake SQS queue URL the collector's GitEventPoller long-polls."
  value       = aws_sqs_queue.codecommit_ingest.url
}

output "queue_arn" {
  description = "CodeCommit intake SQS queue ARN (for the collector task-role consume grant)."
  value       = aws_sqs_queue.codecommit_ingest.arn
}

output "cross_account_event_bus_arn" {
  description = "ARN of the custom event bus the repo account must forward CodeCommit events onto. Empty in same-account topology."
  value       = local.cross_account ? aws_cloudwatch_event_bus.codecommit_xacct[0].arn : ""
}
