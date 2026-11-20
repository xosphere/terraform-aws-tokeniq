output "gateway_endpoint" {
  description = "Point Claude Code here: ANTHROPIC_BASE_URL."
  value       = module.tokeniq.gateway_endpoint
}

output "collector_endpoint" {
  description = "Collector endpoint (developer laptop sync, gateway telemetry)."
  value       = module.tokeniq.collector_endpoint
}

output "developer_onboarding_command" {
  description = "Command each developer runs to sync local agent sessions."
  value       = module.tokeniq.developer_onboarding_command
}

output "gateway_redis_endpoint" {
  description = "Bundled gateway Redis host:port (empty when gateway_redis_mode is \"none\")."
  value       = module.tokeniq.gateway_redis_endpoint
}
