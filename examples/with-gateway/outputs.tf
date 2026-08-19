output "gateway_endpoint" {
  description = "Point ANTHROPIC_BASE_URL (or any OpenAI-compatible client) here."
  value       = module.tokeniq.gateway_endpoint
}

output "gateway_bundle_bucket" {
  description = "Publish signed bundles to v1/bundles/latest in this bucket."
  value       = module.tokeniq.gateway_bundle_bucket
}

output "gateway_admin_token_secret_arn" {
  description = "Read the admin console token from this secret."
  value       = module.tokeniq.gateway_admin_token_secret_arn
}

output "collector_endpoint" {
  description = "Collector base URL for tokeniq sync."
  value       = module.tokeniq.collector_endpoint
}

output "developer_onboarding_command" {
  description = "Paste-ready tokeniq sync enrollment command."
  value       = module.tokeniq.developer_onboarding_command
}
