output "alb_dns_name" {
  description = "Public ALB DNS name (use this for load testing)"
  value       = aws_lb.main.dns_name
}

output "internal_nlb_dns_name" {
  description = "Internal NLB DNS name (service-to-service communication)"
  value       = aws_lb.internal.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "task_definition_arns" {
  description = "Task definition ARNs for ECS services"
  value = {
    product                = aws_ecs_task_definition.product.arn
    credit_card_authorizer = aws_ecs_task_definition.credit_card_authorizer.arn
    warehouse              = aws_ecs_task_definition.warehouse.arn
    rabbitmq               = aws_ecs_task_definition.rabbitmq.arn
    shopping_cart          = aws_ecs_task_definition.shopping_cart.arn
  }
}

output "ecs_service_names" {
  description = "ECS service names"
  value = {
    product                = aws_ecs_service.product.name
    credit_card_authorizer = aws_ecs_service.credit_card_authorizer.name
    warehouse              = aws_ecs_service.warehouse.name
    rabbitmq               = aws_ecs_service.rabbitmq.name
    shopping_cart          = aws_ecs_service.shopping_cart.name
  }
}

output "autoscaling_limits" {
  description = "Autoscaling min/max capacities (warehouse is fixed single task, no App Auto Scaling)"
  value = {
    product = {
      min = aws_appautoscaling_target.product.min_capacity
      max = aws_appautoscaling_target.product.max_capacity
    }
    shopping_cart = {
      min = aws_appautoscaling_target.shopping_cart.min_capacity
      max = aws_appautoscaling_target.shopping_cart.max_capacity
    }
    credit_card_authorizer = {
      min = aws_appautoscaling_target.credit_card_authorizer.min_capacity
      max = aws_appautoscaling_target.credit_card_authorizer.max_capacity
    }
  }
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = { for k, r in aws_ecr_repository.services : k => r.repository_url }
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb      = aws_security_group.alb.id
    services = aws_security_group.services.id
    kv_ec2   = aws_security_group.kv_ec2.id
  }
}

# ── KV Database EC2 Outputs ────────────────────────────────────────────────────

output "kv_products_config" {
  description = "KV Products cluster configuration"
  value = {
    mode           = var.kv_products_mode
    node_count     = var.kv_products_node_count
    write_quorum   = var.kv_products_write_quorum
    read_quorum    = var.kv_products_read_quorum
    leader_ip      = var.kv_products_mode == "leader-follower" ? (length(aws_instance.kv_products_leader) > 0 ? aws_instance.kv_products_leader[0].private_ip : null) : null
    follower_ips   = var.kv_products_mode == "leader-follower" ? aws_instance.kv_products_followers[*].private_ip : []
    leaderless_ips = var.kv_products_mode == "leaderless" ? aws_instance.kv_products_leaderless[*].private_ip : []
  }
}

output "kv_carts_config" {
  description = "KV Carts cluster configuration"
  value = {
    mode           = var.kv_carts_mode
    node_count     = var.kv_carts_node_count
    write_quorum   = var.kv_carts_write_quorum
    read_quorum    = var.kv_carts_read_quorum
    leader_ip      = var.kv_carts_mode == "leader-follower" ? (length(aws_instance.kv_carts_leader) > 0 ? aws_instance.kv_carts_leader[0].private_ip : null) : null
    follower_ips   = var.kv_carts_mode == "leader-follower" ? aws_instance.kv_carts_followers[*].private_ip : []
    leaderless_ips = var.kv_carts_mode == "leaderless" ? aws_instance.kv_carts_leaderless[*].private_ip : []
  }
}

output "kv_ec2_public_ips" {
  description = "Public IPs of all KV EC2 instances (for SSH debugging)"
  value = {
    products = concat(
      var.kv_products_mode == "leader-follower" ? aws_instance.kv_products_leader[*].public_ip : [],
      var.kv_products_mode == "leader-follower" ? aws_instance.kv_products_followers[*].public_ip : [],
      var.kv_products_mode == "leaderless" ? aws_instance.kv_products_leaderless[*].public_ip : [],
    )
    carts = concat(
      var.kv_carts_mode == "leader-follower" ? aws_instance.kv_carts_leader[*].public_ip : [],
      var.kv_carts_mode == "leader-follower" ? aws_instance.kv_carts_followers[*].public_ip : [],
      var.kv_carts_mode == "leaderless" ? aws_instance.kv_carts_leaderless[*].public_ip : [],
    )
  }
}
