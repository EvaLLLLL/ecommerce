# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC ALB (product + shopping cart)
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb" })
}

resource "aws_lb_target_group" "product" {
  name        = "${var.project_name}-product"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "cart" {
  name        = "${var.project_name}-cart"
  port        = 8082
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 15
    interval            = 30
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"Not Found\"}"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "product" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.product.arn
  }

  condition {
    path_pattern {
      values = ["/product", "/product/*", "/products", "/products/*"]
    }
  }
}

resource "aws_lb_listener_rule" "cart" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cart.arn
  }

  condition {
    path_pattern {
      values = ["/shopping-cart", "/shopping-cart/*", "/shopping-carts", "/shopping-carts/*"]
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL NLB (CCA, warehouse, RabbitMQ, KV databases)
# One NLB, different ports for different services.
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_lb" "internal" {
  name                             = "${var.project_name}-internal"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = data.aws_subnets.default.ids
  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, { Name = "${var.project_name}-internal-nlb" })
}

# ── CCA (:8081) ─────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "cca" {
  name        = "${var.project_name}-cca"
  port        = 8081
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = "traffic-port"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "cca" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 8081
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cca.arn
  }
}

# ── Warehouse (:8083) ───────────────────────────────────────────────────────

resource "aws_lb_target_group" "warehouse" {
  name        = "${var.project_name}-warehouse"
  port        = 8083
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = "traffic-port"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "warehouse" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 8083
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.warehouse.arn
  }
}

# ── RabbitMQ AMQP (:5672) ──────────────────────────────────────────────────

resource "aws_lb_target_group" "rabbitmq" {
  name        = "${var.project_name}-rabbitmq"
  port        = 5672
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "rabbitmq" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 5672
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq.arn
  }
}

# ── KV Products (:8084) — targets registered in kv-ec2.tf ──────────────────

resource "aws_lb_target_group" "kv_products" {
  name        = "${var.project_name}-kv-products"
  port        = 8084
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = "traffic-port"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "kv_products" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 8084
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kv_products.arn
  }
}

# ── KV Carts (:8085) — targets registered in kv-ec2.tf ─────────────────────

resource "aws_lb_target_group" "kv_carts" {
  name        = "${var.project_name}-kv-carts"
  port        = 8085
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = "traffic-port"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "kv_carts" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 8085
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kv_carts.arn
  }
}
