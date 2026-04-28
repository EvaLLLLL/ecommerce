# ── Public ALB Security Group ────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Public ALB - allow HTTP from anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-alb-sg" })
}

# ── ECS Services Security Group ─────────────────────────────────────────────

resource "aws_security_group" "services" {
  name_prefix = "${var.project_name}-services-"
  description = "ECS tasks - ALB + internal service-to-service"
  vpc_id      = data.aws_vpc.default.id

  # ALB -> containers (product 8080, CCA 8081, cart 8082, warehouse 8083, kv 8084)
  ingress {
    description     = "From public ALB"
    from_port       = 8080
    to_port         = 8084
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Service-to-service via internal NLB (all ports, self-referencing)
  ingress {
    description = "Internal service traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Allow VPC CIDR for NLB health checks
  ingress {
    description = "VPC internal (NLB health checks)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-services-sg" })
}
