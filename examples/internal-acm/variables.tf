variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "vpc_id" {
  description = "VPC the data plane deploys into (developers must reach it via VPN/DirectConnect/peering)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the services and the internal NLB."
  type        = list(string)
}

variable "tenant_id" {
  description = "Tenant identifier stamped on all telemetry."
  type        = string
}

variable "image_registry" {
  description = "Container registry holding the TokenIQ images."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate covering dns_name, for the NLB TLS listener."
  type        = string
}

variable "dns_name" {
  description = "Fully qualified DNS name developers call the collector by (e.g. tokeniq.example.com). Must be covered by the ACM certificate."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone to create the collector alias record in. Empty skips DNS (point your own DNS at the nlb_dns_name output instead)."
  type        = string
  default     = ""
}
