output "vpc_endpoint_id" {
  description = "ID of the hosted-plane ingest interface endpoint."
  value       = aws_vpc_endpoint.ingest.id
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries of the interface endpoint (the endpoint-specific names; the vendor's private DNS name also resolves in-VPC)."
  value       = aws_vpc_endpoint.ingest.dns_entry
}
