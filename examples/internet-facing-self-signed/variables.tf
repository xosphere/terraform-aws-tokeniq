variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "vpc_id" {
  description = "VPC the data plane deploys into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets the services run in."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnets for the internet-facing NLB."
  type        = list(string)
}

variable "developer_egress_cidrs" {
  description = "CIDRs your developers' sync traffic egresses from (office/home IPs). The only ranges allowed to reach the collector on 443 — never 0.0.0.0/0."
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
