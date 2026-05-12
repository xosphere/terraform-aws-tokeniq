output "turns_bucket_name" {
  description = "S3 bucket for raw LLM turns (configure in LiteLLM s3_v2 callback)"
  value       = aws_s3_bucket.turns_raw.id
}

output "turns_table_name" {
  description = "DynamoDB table for processed turns"
  value       = aws_dynamodb_table.turns.name
}

output "sessions_table_name" {
  description = "DynamoDB table for session aggregates"
  value       = aws_dynamodb_table.sessions.name
}

output "ingest_lambda_arn" {
  description = "ARN of the ingest Lambda function"
  value       = aws_lambda_function.ingest.arn
}

output "plan_attributions_table_name" {
  description = "DynamoDB table for plan attributions and time estimates"
  value       = aws_dynamodb_table.plan_attributions.name
}

output "plan_analyzer_enabled" {
  description = "Whether the plan-analyzer Lambda is deployed (requires anthropic_api_key)"
  value       = local.has_anthropic_key
}

output "dashboard_api_url" {
  description = "Dashboard API endpoint URL (configure as Grafana JSON API data source)"
  value       = var.grafana_enabled ? "https://${aws_apigatewayv2_api.dashboard[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com" : null
}

output "grafana_workspace_url" {
  description = "Amazon Managed Grafana workspace URL"
  value       = var.grafana_enabled ? aws_grafana_workspace.tokeniq[0].endpoint : null
}
