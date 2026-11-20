# Bundled Redis (redis_mode = "bundled"): a small ElastiCache replication
# group the gateway tasks share. With it, rate limits are enforced across
# every task instead of per task, budgets are enforced, the response cache
# and the cost estimator's running averages are shared, and SSO /login
# state survives a callback landing on a different replica. Without it
# (redis_mode = "none") the gateway still serves, with per-task rate limits,
# budgets off and no response cache.
#
# Plaintext and no AUTH on purpose: the gateway's Redis client cannot yet
# speak TLS or AUTH (TGWY-248), so transit encryption or an auth token
# would make Redis unreachable. Isolation is the network: private subnets
# only, and a security group that admits 6379 from the gateway tasks'
# security group and nothing else. Data at rest is encrypted.

locals {
  redis_enabled = var.redis_mode == "bundled"
  redis_port    = 6379

  redis_engine_version = (
    var.redis_engine_version != "" ? var.redis_engine_version :
    var.redis_engine == "valkey" ? "8.0" : "7.1"
  )

  # ElastiCache replication group IDs: at most 40 characters, lowercase
  # letters, digits and single hyphens, starting with a letter and not
  # ending with a hyphen. Long prefixes are truncated and disambiguated
  # with a short hash of the full name so two long prefixes never collide.
  redis_name_raw = replace(replace(lower("${var.name_prefix}-gateway-redis"), "/[^a-z0-9-]/", "-"), "/-{2,}/", "-")
  redis_name = (
    length(local.redis_name_raw) <= 40 ? local.redis_name_raw :
    "${replace(substr(local.redis_name_raw, 0, 31), "/-+$/", "")}-${substr(md5(local.redis_name_raw), 0, 8)}"
  )

  # host:port the gateway dials (TOKENIQ_REDIS_ADDR); empty when not bundled.
  redis_addr = local.redis_enabled ? "${aws_elasticache_replication_group.redis[0].primary_endpoint_address}:${local.redis_port}" : ""
}

resource "aws_elasticache_subnet_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  name        = local.redis_name
  description = "TokenIQ Gateway Redis"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = local.redis_name
  }
}

resource "aws_security_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  name        = "${var.name_prefix}-gateway-redis"
  description = "TokenIQ Gateway Redis: 6379 from the gateway tasks only"
  vpc_id      = var.vpc_id

  # The only ingress. No egress rules: Redis never initiates connections,
  # and declaring none makes Terraform drop the default allow-all egress.
  ingress {
    description     = "Redis from the gateway tasks"
    from_port       = local.redis_port
    to_port         = local.redis_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${var.name_prefix}-gateway-redis"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  replication_group_id = local.redis_name
  description          = "TokenIQ Gateway shared state (rate limits, budgets, response cache)"

  engine         = var.redis_engine
  engine_version = local.redis_engine_version
  node_type      = var.redis_node_type
  port           = local.redis_port

  # Primary + one replica in different AZs; ElastiCache promotes the
  # replica and repoints the primary endpoint on failure, so the gateway
  # always dials the primary endpoint, never a node.
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.redis[0].id]

  at_rest_encryption_enabled = true
  # The gateway cannot speak TLS or AUTH to Redis yet (TGWY-248): no
  # transit encryption and no auth_token. Isolation is the security group
  # above plus private subnets.
  transit_encryption_enabled = false

  snapshot_retention_limit = 1
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:05:00-sun:06:00"
  apply_immediately        = false

  tags = {
    Name = local.redis_name
  }
}
