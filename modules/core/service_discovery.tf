# --- Service discovery ---
# Private DNS namespaces are VPC-wide, so consumers on any ECS cluster in the
# VPC resolve these names.

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = var.discovery_namespace
  vpc  = var.vpc_id
}

# collector.<namespace> — in-VPC ingest endpoint.
resource "aws_service_discovery_service" "collector" {
  name = "collector"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  # failure_threshold is deprecated (AWS always reports 1) and the provider
  # refreshes a populated block to empty; without ignore_changes Terraform then
  # plans to re-add it every apply, which is ForceNew and destroys the live
  # Cloud Map service. Set once at create, ignored thereafter.
  health_check_custom_config {}

  lifecycle {
    ignore_changes = [health_check_custom_config]
  }
}

# data-service.<namespace> — the enricher's pattern engine calls its REST
# surface here.
resource "aws_service_discovery_service" "data_service" {
  name = "data-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config {}

  lifecycle {
    ignore_changes = [health_check_custom_config]
  }
}
