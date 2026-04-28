# ═══════════════════════════════════════════════════════════════════════════════
# KV DATABASE — EC2 INSTANCES
# ═══════════════════════════════════════════════════════════════════════════════
#
# Two clusters: kv-products (port 8084) and kv-carts (port 8085).
# Each can run in leader-follower or leaderless mode — controlled by variables.
#
# Leader-Follower (default):
#   1 leader + (N-1) followers.  FOLLOWER_URLS injected via user_data.
#   No SSH key required.
#
# Leaderless:
#   N equal peers.  PEER_URLS set via null_resource remote-exec.
#   Requires kv_key_name + kv_private_key_path for SSH.
#
# Tuning knobs (all in variables.tf):
#   kv_<cluster>_mode         "leader-follower" | "leaderless"
#   kv_<cluster>_node_count   N  (total nodes in the cluster)
#   kv_<cluster>_write_quorum W
#   kv_<cluster>_read_quorum  R
#   kv_instance_type          EC2 instance size (default t3.micro)

locals {
  kv_products_port = 8084
  kv_carts_port    = 8085
  kv_ecr_image     = "${aws_ecr_repository.services["kv_database"].repository_url}:latest"
  kv_ecr_registry  = split("/", aws_ecr_repository.services["kv_database"].repository_url)[0]
  kv_ami_id        = var.kv_ami_id != "" ? var.kv_ami_id : data.aws_ami.amazon_linux_2023.id
}

# ── Security Group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "kv_ec2" {
  name_prefix = "${var.project_name}-kv-ec2-"
  description = "KV database EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  # From VPC — NLB health checks + ECS services via NLB
  ingress {
    description = "Application traffic from VPC"
    from_port   = 8080
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # Node-to-node replication
  ingress {
    description = "Inter-node replication"
    from_port   = 8080
    to_port     = 8090
    protocol    = "tcp"
    self        = true
  }

  # SSH — for leaderless provisioning & debugging
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-kv-ec2-sg" })
}

# ═══════════════════════════════════════════════════════════════════════════════
# PRODUCTS CLUSTER  (port 8084,  default: leader-follower, N=3, W=3, R=1)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Leader-Follower: Followers ─────────────────────────────────────────────────

resource "aws_instance" "kv_products_followers" {
  count = var.kv_products_mode == "leader-follower" ? var.kv_products_node_count - 1 : 0

  ami                         = local.kv_ami_id
  instance_type               = var.kv_instance_type
  subnet_id                   = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids      = [aws_security_group.kv_ec2.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  key_name                    = var.kv_key_name != "" ? var.kv_key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/kv-user-data.sh.tpl", {
    aws_region    = var.aws_region
    ecr_registry  = local.kv_ecr_registry
    image         = local.kv_ecr_image
    port          = local.kv_products_port
    role          = "follower"
    follower_urls = ""
    write_quorum  = 0
    read_quorum   = 0
  }))

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-kv-products-f${count.index + 1}"
    Role    = "follower"
    Cluster = "kv-products"
  })
}

# ── Leader-Follower: Leader ────────────────────────────────────────────────────

resource "aws_instance" "kv_products_leader" {
  count = var.kv_products_mode == "leader-follower" ? 1 : 0

  ami                         = local.kv_ami_id
  instance_type               = var.kv_instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.kv_ec2.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  key_name                    = var.kv_key_name != "" ? var.kv_key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/kv-user-data.sh.tpl", {
    aws_region    = var.aws_region
    ecr_registry  = local.kv_ecr_registry
    image         = local.kv_ecr_image
    port          = local.kv_products_port
    role          = "leader"
    follower_urls = join(",", [for ip in aws_instance.kv_products_followers[*].private_ip : "http://${ip}:${local.kv_products_port}"])
    write_quorum  = var.kv_products_write_quorum
    read_quorum   = var.kv_products_read_quorum
  }))

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-kv-products-leader"
    Role    = "leader"
    Cluster = "kv-products"
  })
}

# ── Leaderless: Nodes ──────────────────────────────────────────────────────────

resource "aws_instance" "kv_products_leaderless" {
  count = var.kv_products_mode == "leaderless" ? var.kv_products_node_count : 0

  ami                         = local.kv_ami_id
  instance_type               = var.kv_instance_type
  subnet_id                   = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids      = [aws_security_group.kv_ec2.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  key_name                    = var.kv_key_name != "" ? var.kv_key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/kv-leaderless-base.sh.tpl", {
    aws_region   = var.aws_region
    ecr_registry = local.kv_ecr_registry
    image        = local.kv_ecr_image
  }))

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-kv-products-node-${count.index + 1}"
    Role    = "leaderless"
    Cluster = "kv-products"
  })
}

# Start containers after all IPs are known (requires SSH)
resource "null_resource" "kv_products_leaderless_start" {
  count = var.kv_products_mode == "leaderless" ? var.kv_products_node_count : 0

  depends_on = [aws_instance.kv_products_leaderless]

  lifecycle {
    precondition {
      condition     = var.kv_key_name != "" && var.kv_private_key_path != ""
      error_message = "Leaderless mode requires kv_key_name and kv_private_key_path for SSH provisioning."
    }
  }

  connection {
    type        = "ssh"
    host        = aws_instance.kv_products_leaderless[count.index].public_ip
    user        = "ec2-user"
    private_key = file(var.kv_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "set -ex",
      "while ! sudo docker info >/dev/null 2>&1; do sleep 2; done",
      "while ! sudo docker image inspect ${local.kv_ecr_image} >/dev/null 2>&1; do sleep 5; done",
      join(" ", [
        "sudo docker run -d --name kv-node --restart unless-stopped",
        "-p ${local.kv_products_port}:${local.kv_products_port}",
        "-e KV_DATABASE_PORT=${local.kv_products_port}",
        "-e ROLE=leaderless",
        "-e PEER_URLS='${join(",", [for i, inst in aws_instance.kv_products_leaderless : "http://${inst.private_ip}:${local.kv_products_port}" if i != count.index])}'",
        "-e WRITE_QUORUM_SIZE=${var.kv_products_write_quorum}",
        "-e READ_QUORUM_SIZE=${var.kv_products_read_quorum}",
        "-e NODE_SELF_URL=http://${aws_instance.kv_products_leaderless[count.index].private_ip}:${local.kv_products_port}",
        local.kv_ecr_image,
      ]),
    ]
  }
}

# ── Products: NLB Target Registration ──────────────────────────────────────────

resource "aws_lb_target_group_attachment" "kv_products_lf" {
  count            = var.kv_products_mode == "leader-follower" ? 1 : 0
  target_group_arn = aws_lb_target_group.kv_products.arn
  target_id        = aws_instance.kv_products_leader[0].id
  port             = local.kv_products_port
}

resource "aws_lb_target_group_attachment" "kv_products_ll" {
  count            = var.kv_products_mode == "leaderless" ? var.kv_products_node_count : 0
  target_group_arn = aws_lb_target_group.kv_products.arn
  target_id        = aws_instance.kv_products_leaderless[count.index].id
  port             = local.kv_products_port
}

# ═══════════════════════════════════════════════════════════════════════════════
# CARTS CLUSTER  (port 8085,  default: leaderless, N=3, W=2, R=2)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Leader-Follower: Followers ─────────────────────────────────────────────────

resource "aws_instance" "kv_carts_followers" {
  count = var.kv_carts_mode == "leader-follower" ? var.kv_carts_node_count - 1 : 0

  ami                         = local.kv_ami_id
  instance_type               = var.kv_instance_type
  subnet_id                   = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids      = [aws_security_group.kv_ec2.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  key_name                    = var.kv_key_name != "" ? var.kv_key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/kv-user-data.sh.tpl", {
    aws_region    = var.aws_region
    ecr_registry  = local.kv_ecr_registry
    image         = local.kv_ecr_image
    port          = local.kv_carts_port
    role          = "follower"
    follower_urls = ""
    write_quorum  = 0
    read_quorum   = 0
  }))

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-kv-carts-f${count.index + 1}"
    Role    = "follower"
    Cluster = "kv-carts"
  })
}

# ── Leader-Follower: Leader ────────────────────────────────────────────────────

resource "aws_instance" "kv_carts_leader" {
  count = var.kv_carts_mode == "leader-follower" ? 1 : 0

  ami                         = local.kv_ami_id
  instance_type               = var.kv_instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.kv_ec2.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  key_name                    = var.kv_key_name != "" ? var.kv_key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/kv-user-data.sh.tpl", {
    aws_region    = var.aws_region
    ecr_registry  = local.kv_ecr_registry
    image         = local.kv_ecr_image
    port          = local.kv_carts_port
    role          = "leader"
    follower_urls = join(",", [for ip in aws_instance.kv_carts_followers[*].private_ip : "http://${ip}:${local.kv_carts_port}"])
    write_quorum  = var.kv_carts_write_quorum
    read_quorum   = var.kv_carts_read_quorum
  }))

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-kv-carts-leader"
    Role    = "leader"
    Cluster = "kv-carts"
  })
}

# ── Leaderless: Nodes ──────────────────────────────────────────────────────────

resource "aws_instance" "kv_carts_leaderless" {
  count = var.kv_carts_mode == "leaderless" ? var.kv_carts_node_count : 0

  ami                         = local.kv_ami_id
  instance_type               = var.kv_instance_type
  subnet_id                   = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids      = [aws_security_group.kv_ec2.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  key_name                    = var.kv_key_name != "" ? var.kv_key_name : null

  user_data = base64encode(templatefile("${path.module}/templates/kv-leaderless-base.sh.tpl", {
    aws_region   = var.aws_region
    ecr_registry = local.kv_ecr_registry
    image        = local.kv_ecr_image
  }))

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-kv-carts-node-${count.index + 1}"
    Role    = "leaderless"
    Cluster = "kv-carts"
  })
}

resource "null_resource" "kv_carts_leaderless_start" {
  count = var.kv_carts_mode == "leaderless" ? var.kv_carts_node_count : 0

  depends_on = [aws_instance.kv_carts_leaderless]

  lifecycle {
    precondition {
      condition     = var.kv_key_name != "" && var.kv_private_key_path != ""
      error_message = "Leaderless mode requires kv_key_name and kv_private_key_path for SSH provisioning."
    }
  }

  connection {
    type        = "ssh"
    host        = aws_instance.kv_carts_leaderless[count.index].public_ip
    user        = "ec2-user"
    private_key = file(var.kv_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "set -ex",
      "while ! sudo docker info >/dev/null 2>&1; do sleep 2; done",
      "while ! sudo docker image inspect ${local.kv_ecr_image} >/dev/null 2>&1; do sleep 5; done",
      join(" ", [
        "sudo docker run -d --name kv-node --restart unless-stopped",
        "-p ${local.kv_carts_port}:${local.kv_carts_port}",
        "-e KV_DATABASE_PORT=${local.kv_carts_port}",
        "-e ROLE=leaderless",
        "-e PEER_URLS='${join(",", [for i, inst in aws_instance.kv_carts_leaderless : "http://${inst.private_ip}:${local.kv_carts_port}" if i != count.index])}'",
        "-e WRITE_QUORUM_SIZE=${var.kv_carts_write_quorum}",
        "-e READ_QUORUM_SIZE=${var.kv_carts_read_quorum}",
        "-e NODE_SELF_URL=http://${aws_instance.kv_carts_leaderless[count.index].private_ip}:${local.kv_carts_port}",
        local.kv_ecr_image,
      ]),
    ]
  }
}

# ── Carts: NLB Target Registration ────────────────────────────────────────────

resource "aws_lb_target_group_attachment" "kv_carts_lf" {
  count            = var.kv_carts_mode == "leader-follower" ? 1 : 0
  target_group_arn = aws_lb_target_group.kv_carts.arn
  target_id        = aws_instance.kv_carts_leader[0].id
  port             = local.kv_carts_port
}

resource "aws_lb_target_group_attachment" "kv_carts_ll" {
  count            = var.kv_carts_mode == "leaderless" ? var.kv_carts_node_count : 0
  target_group_arn = aws_lb_target_group.kv_carts.arn
  target_id        = aws_instance.kv_carts_leaderless[count.index].id
  port             = local.kv_carts_port
}
