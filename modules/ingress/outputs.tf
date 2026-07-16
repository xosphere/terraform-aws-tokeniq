output "target_group_arn" {
  description = "NLB target group the collector ECS service registers into. Empty when no load balancer is created."
  value       = var.create_load_balancer ? aws_lb_target_group.collector[0].arn : ""
}

output "nlb_dns_name" {
  description = "DNS name of the collector NLB. Empty when no load balancer is created."
  value       = var.create_load_balancer ? aws_lb.collector[0].dns_name : ""
}

output "collector_endpoint" {
  description = "Base URL clients call the collector at: the custom DNS name when set, else the NLB DNS name, else the in-VPC Cloud Map name."
  value = (
    var.dns_name != "" ? "https://${var.dns_name}" :
    var.create_load_balancer ? "https://${aws_lb.collector[0].dns_name}" :
    "https://collector.${var.discovery_namespace}:8080"
  )
}

output "client_ca_required" {
  description = "true when clients must trust collector_ca_pem (self-signed handshake); false in \"acm\" mode."
  value       = var.tls_mode == "self_signed" || !var.create_load_balancer
}

output "collector_ca_pem" {
  description = "PEM certificate clients must trust (tokeniq sync configure --collector-ca). Populated only when clients handshake with the self-signed cert (tls_mode = \"self_signed\" or no load balancer); empty in \"acm\" mode, where system roots suffice."
  value       = var.tls_mode == "self_signed" || !var.create_load_balancer ? tls_self_signed_cert.collector.cert_pem : ""
  sensitive   = true
}
