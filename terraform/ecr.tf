# One ECR repository per service image.
# Image naming: ${var.project_name}-<service>
# Tag convention: use git SHA for CI, "latest" for manual pushes.

locals {
  # Map of logical name → ECR repo suffix
  ecr_services = {
    product                = "product-service"
    shopping_cart          = "shopping-cart-service"
    credit_card_authorizer = "credit-card-authorizer-service"
    warehouse              = "warehouse-service"
    rabbitmq               = "rabbitmq"
    kv_database            = "kv-database"
  }
}

resource "aws_ecr_repository" "services" {
  for_each             = local.ecr_services
  name                 = "${var.project_name}-${each.value}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${each.value}"
  })
}
