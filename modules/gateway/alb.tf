# --- Application Load Balancer ---
#
# The gateway fronts with an ALB (not the collector's NLB): it needs
# path-based routing for /admin*, HTTP health checks, and a long idle
# timeout for streaming inference.

resource "aws_lb" "gateway" {
  name               = "${var.name_prefix}-gateway"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.alb_subnet_ids

  enable_deletion_protection = var.alb_deletion_protection

  # The AWS default of 60s cuts long inference calls mid-flight. Must stay
  # ABOVE the gateway's write timeout — the timeout ladder, innermost out:
  # upstream attempt < write timeout < ALB idle.
  idle_timeout = var.alb_idle_timeout
}

resource "aws_lb_target_group" "gateway" {
  name        = "${var.name_prefix}-gateway"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = 8080
    protocol            = "HTTP"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# The admin server listens on its own port, so it needs its own target
# group. The health check hits the console's index rather than an API
# route: the SPA is served unauthenticated, while every /admin/api/ route
# 401s without the bearer token.
resource "aws_lb_target_group" "admin" {
  name        = "${var.name_prefix}-gateway-admin"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/admin/"
    port                = 8081
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.gateway.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

# /admin* is the only path pulled off the default action. The data-plane
# routes (/v1/*, /mcp/*) never collide with it, so they fall through to
# the gateway target group untouched. Access control is the admin bearer
# token plus the ALB's reachability (internal + allowed_ingress_cidrs by
# default).
resource "aws_lb_listener_rule" "admin" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin*"]
    }
  }
}

resource "aws_route53_record" "gateway" {
  count = var.route53_zone_id != "" && var.dns_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.dns_name
  type    = "A"

  alias {
    name                   = aws_lb.gateway.dns_name
    zone_id                = aws_lb.gateway.zone_id
    evaluate_target_health = true
  }
}
