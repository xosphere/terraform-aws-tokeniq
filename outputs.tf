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
