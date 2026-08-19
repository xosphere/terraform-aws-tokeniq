output "gateway_endpoint" {
  description = "Base URL clients call the gateway at: the custom DNS name when set, else the ALB DNS name."
  value       = var.dns_name != "" ? "https://${var.dns_name}" : "https://${aws_lb.gateway.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the gateway ALB."
  value       = aws_lb.gateway.dns_name
}

output "bundle_url" {
  description = "Bundle-source base URL the gateway polls (the module-owned bucket's REST endpoint in Tier 2, or the configured bundle_url)."
  value       = local.bundle_url
}

output "bundle_bucket" {
  description = "Name of the module-owned Tier 2 bundle bucket; empty when bundle_url points elsewhere. Publish signed artifacts to key v1/bundles/latest."
  value       = var.bundle_url == "" ? aws_s3_bucket.bundle[0].bucket : ""
}

output "admin_token_secret_arn" {
  description = "Secrets Manager ARN holding the admin console bearer token."
  value       = aws_secretsmanager_secret.admin_token.arn
}

output "task_role_arn" {
  description = "Task role the gateway runs as (extend for additional AWS-authenticated providers)."
  value       = aws_iam_role.task.arn
}

output "ecs_security_group_id" {
  description = "Security group of the gateway tasks (reference to allow gateway egress into other services)."
  value       = aws_security_group.ecs.id
}
