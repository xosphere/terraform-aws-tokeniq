data "aws_vpc" "this" {
  id = var.vpc_id
}

locals {
  # Internal NLB with no explicit CIDRs defaults to the whole VPC (covers
  # VPN/peering ranges routed into it). Internet-facing REQUIRES explicit
  # CIDRs (enforced by variable validation).
  allowed_cidrs = length(var.allowed_ingress_cidrs) > 0 ? var.allowed_ingress_cidrs : [data.aws_vpc.this.cidr_block]
}

resource "aws_security_group" "nlb" {
  count = var.create_load_balancer ? 1 : 0

  name_prefix = "${var.name_prefix}-collector-nlb-"
  description = "TokenIQ collector NLB"
  vpc_id      = var.vpc_id

  ingress {
    description = "Collector TLS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.allowed_cidrs
  }

  egress {
    description = "To collector tasks"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "collector" {
  count = var.create_load_balancer ? 1 : 0

  name               = "${var.name_prefix}-collector"
  load_balancer_type = "network"
  internal           = !var.internet_facing
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.nlb[0].id]
}

resource "aws_lb_target_group" "collector" {
  count = var.create_load_balancer ? 1 : 0

  name        = "${var.name_prefix}-collector"
  port        = 8080
  protocol    = var.tls_mode == "acm" ? "TLS" : "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # Traffic reaches the tasks from the NLB's private node IPs (inside the VPC
  # CIDR the collector SG already allows), so internet client IPs never need
  # task-SG rules. The collector reads the real client IP from the request.
  preserve_client_ip = false

  # NLB HTTPS health checks do not validate the target cert, so the
  # self-signed cert passes.
  health_check {
    protocol = "HTTPS"
    path     = "/healthz"
    port     = "traffic-port"
  }
}

resource "aws_lb_listener" "collector" {
  count = var.create_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.collector[0].arn
  port              = 443

  # "acm": terminate client TLS at the NLB with the ACM cert, re-encrypt to
  # the task. "self_signed": raw TCP passthrough — the client handshakes
  # directly with the collector's self-signed cert.
  protocol        = var.tls_mode == "acm" ? "TLS" : "TCP"
  certificate_arn = var.tls_mode == "acm" ? var.acm_certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.collector[0].arn
  }
}

resource "aws_route53_record" "collector" {
  count = var.create_load_balancer && var.route53_zone_id != "" && var.dns_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.dns_name
  type    = "A"

  alias {
    name                   = aws_lb.collector[0].dns_name
    zone_id                = aws_lb.collector[0].zone_id
    evaluate_target_health = true
  }
}
