# ── ECS Cluster ─────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-cluster" })
}

# ── CloudWatch Log Group ────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "services" {
  name              = "/ecs/${var.project_name}/services"
  retention_in_days = 7
  tags              = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC SERVICES (behind ALB)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Product Service ─────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "product" {
  family                   = "${var.project_name}-product"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "4096"
  memory                   = "8192"
  execution_role_arn       = local.ecs_task_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = "product-service"
    image        = "${aws_ecr_repository.services["product"].repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "KV_DATABASE_URL", value = "http://${aws_lb.internal.dns_name}:8084" },
      { name = "FAULT_RATE", value = tostring(var.fault_rate) },
      { name = "BAD_INSTANCE_CHANCE", value = tostring(var.bad_instance_chance) }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:8080/health || exit 1"]
      interval    = 20
      timeout     = 5
      retries     = 5
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "product"
      }
    }
  }])
}

resource "aws_ecs_service" "product" {
  name            = "${var.project_name}-product"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.product.arn
  desired_count   = var.product_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.services.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.product.arn
    container_name   = "product-service"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 180
  depends_on                        = [aws_lb_listener.http]

  # Application Auto Scaling (autoscaling.tf) adjusts desired_count; leave it alone after apply.
  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ── Shopping Cart Service ───────────────────────────────────────────────────

resource "aws_ecs_task_definition" "shopping_cart" {
  family                   = "${var.project_name}-shopping-cart"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "4096"
  memory                   = "8192"
  execution_role_arn       = local.ecs_task_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = "shopping-cart-service"
    image        = "${aws_ecr_repository.services["shopping_cart"].repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8082, protocol = "tcp" }]
    environment = [
      { name = "SERVER_PORT", value = "8082" },
      { name = "PRODUCT_SERVICE_URL", value = "http://${aws_lb.main.dns_name}" },
      { name = "CCA_SERVICE_URL", value = "http://${aws_lb.internal.dns_name}:8081" },
      { name = "WAREHOUSE_SERVICE_URL", value = "http://${aws_lb.internal.dns_name}:8083" },
      { name = "KV_DATABASE_URL", value = "http://${aws_lb.internal.dns_name}:8085" },
      { name = "RABBITMQ_HOST", value = aws_lb.internal.dns_name },
      { name = "RABBITMQ_PORT", value = "5672" },
      { name = "RABBITMQ_USERNAME", value = "guest" },
      { name = "RABBITMQ_PASSWORD", value = "guest" },
      { name = "WAREHOUSE_QUEUE_NAME", value = "warehouse.ship.queue" }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:8082/health || exit 1"]
      interval    = 20
      timeout     = 5
      retries     = 5
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "shopping-cart"
      }
    }
  }])
}

resource "aws_ecs_service" "shopping_cart" {
  name            = "${var.project_name}-shopping-cart"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.shopping_cart.arn
  desired_count   = var.microservice_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.services.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.cart.arn
    container_name   = "shopping-cart-service"
    container_port   = 8082
  }

  health_check_grace_period_seconds = 180
  depends_on                        = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL SERVICES (behind internal NLB)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Credit Card Authorizer (NLB :8081) ──────────────────────────────────────

resource "aws_ecs_task_definition" "credit_card_authorizer" {
  family                   = "${var.project_name}-credit-card-authorizer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.ecs_task_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = "credit-card-authorizer"
    image        = "${aws_ecr_repository.services["credit_card_authorizer"].repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8081, protocol = "tcp" }]
    environment = [
      { name = "SERVER_PORT", value = "8081" }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:8081/health || exit 1"]
      interval    = 20
      timeout     = 5
      retries     = 5
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "cca"
      }
    }
  }])
}

resource "aws_ecs_service" "credit_card_authorizer" {
  name            = "${var.project_name}-cca"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.credit_card_authorizer.arn
  desired_count   = var.microservice_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.services.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.cca.arn
    container_name   = "credit-card-authorizer"
    container_port   = 8081
  }

  health_check_grace_period_seconds = 180
  depends_on                        = [aws_lb_listener.cca]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ── Warehouse Service (NLB :8083) ───────────────────────────────────────────

resource "aws_ecs_task_definition" "warehouse" {
  family                   = "${var.project_name}-warehouse"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "4096"
  memory                   = "8192"
  execution_role_arn       = local.ecs_task_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name         = "warehouse-service"
    image        = "${aws_ecr_repository.services["warehouse"].repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 8083, protocol = "tcp" }]
    environment = [
      { name = "SERVER_PORT", value = "8083" },
      { name = "RABBITMQ_HOST", value = aws_lb.internal.dns_name },
      { name = "RABBITMQ_PORT", value = "5672" },
      { name = "RABBITMQ_USERNAME", value = "guest" },
      { name = "RABBITMQ_PASSWORD", value = "guest" },
      { name = "WAREHOUSE_QUEUE_NAME", value = "warehouse.ship.queue" },
      { name = "WAREHOUSE_CONSUMER_COUNT", value = tostring(var.warehouse_consumer_count) },
      { name = "WAREHOUSE_MAX_CONSUMER_COUNT", value = tostring(var.warehouse_max_consumer_count) },
      { name = "WAREHOUSE_PREFETCH_COUNT", value = tostring(var.warehouse_prefetch_count) }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:8083/health || exit 1"]
      interval    = 20
      timeout     = 5
      retries     = 5
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "warehouse"
      }
    }
  }])
}

resource "aws_ecs_service" "warehouse" {
  name            = "${var.project_name}-warehouse"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.warehouse.arn
  desired_count   = var.microservice_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.services.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.warehouse.arn
    container_name   = "warehouse-service"
    container_port   = 8083
  }

  health_check_grace_period_seconds = 180
  depends_on                        = [aws_lb_listener.warehouse, aws_ecs_service.rabbitmq]
}

# ── RabbitMQ (NLB :5672) ────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "${var.project_name}-rabbitmq"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = local.ecs_task_role_arn
  task_role_arn            = local.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = "rabbitmq"
    image     = "${aws_ecr_repository.services["rabbitmq"].repository_url}:latest"
    essential = true
    portMappings = [
      { containerPort = 5672, protocol = "tcp" },
      { containerPort = 15672, protocol = "tcp" }
    ]
    environment = [
      { name = "RABBITMQ_DEFAULT_USER", value = "guest" },
      { name = "RABBITMQ_DEFAULT_PASS", value = "guest" },
      { name = "RABBITMQ_ERLANG_COOKIE", value = "ecommerce-rabbit-cookie" }
    ]
    user = "rabbitmq"
    healthCheck = {
      command     = ["CMD", "rabbitmq-diagnostics", "check_port_connectivity"]
      interval    = 15
      timeout     = 5
      retries     = 5
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.services.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "rabbitmq"
      }
    }
  }])
}

resource "aws_ecs_service" "rabbitmq" {
  name            = "${var.project_name}-rabbitmq"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = var.rabbitmq_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.services.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rabbitmq.arn
    container_name   = "rabbitmq"
    container_port   = 5672
  }

  health_check_grace_period_seconds = 180
  depends_on                        = [aws_lb_listener.rabbitmq]
}
