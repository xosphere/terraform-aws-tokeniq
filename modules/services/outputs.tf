output "collector_security_group_id" {
  description = "Collector task security group. The ingress module adds NLB / allowed-CIDR rules to it."
  value       = aws_security_group.collector.id
}

output "collector_execution_role_arn" {
  description = "Collector ECS execution role ARN. Grant it read on the vendor-hosted export tenant-key secret when export is enabled."
  value       = aws_iam_role.collector_execution.arn
}

output "enricher_execution_role_arn" {
  description = "Enricher ECS execution role ARN. Grant it read on the vendor-hosted export tenant-key secret when export is enabled."
  value       = aws_iam_role.enricher_execution.arn
}

output "collector_service_name" {
  description = "Collector ECS service name."
  value       = aws_ecs_service.collector.name
}

output "enricher_service_name" {
  description = "Enricher ECS service name."
  value       = aws_ecs_service.enricher.name
}

output "data_service_service_name" {
  description = "data-service ECS service name (on its own EC2 cluster)."
  value       = aws_ecs_service.data_service.name
}

output "data_service_cluster_arn" {
  description = "Dedicated EC2 ECS cluster the data-service runs on."
  value       = aws_ecs_cluster.data_service.arn
}
