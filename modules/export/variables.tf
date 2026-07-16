variable "name_prefix" {
  description = "Prefix for the endpoint security group name."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the interface endpoint in (the VPC the exporting tasks run in)."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the interface endpoint ENIs. Use the subnets the collector and enricher tasks run in."
  type        = list(string)
}

variable "endpoint_service_name" {
  description = "Vendor-published PrivateLink endpoint-service name (vpce-svc-...) for the hosted-plane ingest, shared out-of-band during onboarding."
  type        = string
}

variable "ingest_port" {
  description = "Port the hosted-plane ingest service listens on behind the endpoint."
  type        = number
  default     = 8080
}
