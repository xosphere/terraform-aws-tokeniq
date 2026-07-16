output "queue_url" {
  description = "LiteLLM intake SQS queue URL the collector long-polls."
  value       = aws_sqs_queue.litellm_ingest.url
}

output "queue_arn" {
  description = "LiteLLM intake SQS queue ARN (for the collector task-role consume grant)."
  value       = aws_sqs_queue.litellm_ingest.arn
}
