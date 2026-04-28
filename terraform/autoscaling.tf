# ── Autoscaling Targets ─────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "product" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.product.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 3
}

resource "aws_appautoscaling_target" "shopping_cart" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.shopping_cart.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 3
}

resource "aws_appautoscaling_target" "credit_card_authorizer" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.credit_card_authorizer.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 3
}

# Warehouse: no App Auto Scaling — single task only so in-memory inventory stays globally
# consistent (see Assignment 5). desired_count is fixed in ecs.tf.

# ── CPU Scaling Policies ───────────────────────────────────────────────────

resource "aws_appautoscaling_policy" "product_cpu" {
  name               = "${var.project_name}-product-cpu"
  service_namespace  = aws_appautoscaling_target.product.service_namespace
  resource_id        = aws_appautoscaling_target.product.resource_id
  scalable_dimension = aws_appautoscaling_target.product.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "shopping_cart_cpu" {
  name               = "${var.project_name}-shopping-cart-cpu"
  service_namespace  = aws_appautoscaling_target.shopping_cart.service_namespace
  resource_id        = aws_appautoscaling_target.shopping_cart.resource_id
  scalable_dimension = aws_appautoscaling_target.shopping_cart.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "credit_card_authorizer_cpu" {
  name               = "${var.project_name}-cca-cpu"
  service_namespace  = aws_appautoscaling_target.credit_card_authorizer.service_namespace
  resource_id        = aws_appautoscaling_target.credit_card_authorizer.resource_id
  scalable_dimension = aws_appautoscaling_target.credit_card_authorizer.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 40.0
  }
}

# ── Memory Scaling Policies ─────────────────────────────────────────────────
# Product, Shopping Cart, and CCA each have CPU (above) + memory target tracking.
# Warehouse is omitted (single fixed task — see comment above).

resource "aws_appautoscaling_policy" "product_memory" {
  name               = "${var.project_name}-product-memory"
  service_namespace  = aws_appautoscaling_target.product.service_namespace
  resource_id        = aws_appautoscaling_target.product.resource_id
  scalable_dimension = aws_appautoscaling_target.product.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "credit_card_authorizer_memory" {
  name               = "${var.project_name}-cca-memory"
  service_namespace  = aws_appautoscaling_target.credit_card_authorizer.service_namespace
  resource_id        = aws_appautoscaling_target.credit_card_authorizer.resource_id
  scalable_dimension = aws_appautoscaling_target.credit_card_authorizer.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "shopping_cart_memory" {
  name               = "${var.project_name}-shopping-cart-memory"
  service_namespace  = aws_appautoscaling_target.shopping_cart.service_namespace
  resource_id        = aws_appautoscaling_target.shopping_cart.resource_id
  scalable_dimension = aws_appautoscaling_target.shopping_cart.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 70.0
  }
}
