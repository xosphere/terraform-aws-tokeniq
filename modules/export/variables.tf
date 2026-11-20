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

variable "service_region" {
  description = "Region of the endpoint service. Empty derives it from endpoint_service_name (com.amazonaws.vpce.<region>.vpce-svc-...). When it differs from the deploy region, the interface endpoint connects cross-region (AWS PrivateLink cross-region connectivity; the provider must list this region in its supported Regions)."
  type        = string
  default     = ""
}

variable "ingest_port" {
  description = "Port the hosted-plane ingest service listens on behind the endpoint."
  type        = number
  default     = 8080
}
