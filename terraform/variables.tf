variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "ecommerce"
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

# ── ECS Service Counts ─────────────────────────────────────────────────────────

variable "product_desired_count" {
  description = "Desired number of good Product service tasks"
  type        = number
  default     = 1
}

variable "microservice_desired_count" {
  description = "Desired number of running non-Product microservice tasks"
  type        = number
  default     = 1
}

variable "rabbitmq_desired_count" {
  description = "Desired number of RabbitMQ broker tasks"
  type        = number
  default     = 1
}

# ── Warehouse RabbitMQ ─────────────────────────────────────────────────────────

variable "warehouse_consumer_count" {
  description = "Number of warehouse concurrent consumers"
  type        = number
  default     = 16
}

variable "warehouse_max_consumer_count" {
  description = "Max number of warehouse concurrent consumers"
  type        = number
  default     = 64
}

variable "warehouse_prefetch_count" {
  description = "Warehouse RabbitMQ prefetch count per consumer"
  type        = number
  default     = 10
}

# ── Product Service ATW Demo ───────────────────────────────────────────────────

variable "fault_rate" {
  description = "Fraction of requests a bad Product Service instance returns 503 (ATW demo)"
  type        = number
  default     = 0.0
}

variable "bad_instance_chance" {
  description = "Probability each Product Service instance becomes a bad instance at startup"
  type        = number
  default     = 0.0
}

# ═══════════════════════════════════════════════════════════════════════════════
# KV DATABASE — EC2 CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
#
# Each KV cluster is configurable independently:
#   mode        → "leader-follower" or "leaderless"
#   node_count  → N (total nodes in cluster, including leader)
#   write_quorum → W
#   read_quorum  → R
#
# Configurations from teammate's Assignment 4 experiments:
#   Products:      leader-follower, N=3, W=3, R=1
#   ShoppingCarts: leaderless,      N=3, W=2, R=2

# ── Products Cluster ───────────────────────────────────────────────────────────

variable "kv_products_mode" {
  description = "Replication mode for Products KV cluster"
  type        = string
  default     = "leader-follower"

  validation {
    condition     = contains(["leader-follower", "leaderless"], var.kv_products_mode)
    error_message = "Must be 'leader-follower' or 'leaderless'."
  }
}

variable "kv_products_node_count" {
  description = "Total number of nodes (N) in the Products KV cluster"
  type        = number
  default     = 3
}

variable "kv_products_write_quorum" {
  description = "Write quorum size (W) for Products KV cluster"
  type        = number
  default     = 3
}

variable "kv_products_read_quorum" {
  description = "Read quorum size (R) for Products KV cluster"
  type        = number
  default     = 1
}

# ── Carts Cluster ──────────────────────────────────────────────────────────────

variable "kv_carts_mode" {
  description = "Replication mode for Carts KV cluster"
  type        = string
  default     = "leaderless"

  validation {
    condition     = contains(["leader-follower", "leaderless"], var.kv_carts_mode)
    error_message = "Must be 'leader-follower' or 'leaderless'."
  }
}

variable "kv_carts_node_count" {
  description = "Total number of nodes (N) in the Carts KV cluster"
  type        = number
  default     = 3
}

variable "kv_carts_write_quorum" {
  description = "Write quorum size (W) for Carts KV cluster"
  type        = number
  default     = 2
}

variable "kv_carts_read_quorum" {
  description = "Read quorum size (R) for Carts KV cluster"
  type        = number
  default     = 2
}

# ── EC2 Instance Settings ──────────────────────────────────────────────────────

variable "kv_instance_type" {
  description = "EC2 instance type for KV database nodes"
  type        = string
  default     = "t3.micro"
}

variable "kv_ami_id" {
  description = "AMI ID for KV EC2 instances. Leave empty to auto-detect Amazon Linux 2023."
  type        = string
  default     = ""
}

variable "kv_key_name" {
  description = "EC2 key pair name for SSH access to KV nodes (optional, required for leaderless mode)"
  type        = string
  default     = "vockey"
}

variable "kv_private_key_path" {
  description = "Path to SSH private key file (only required for leaderless mode provisioning)"
  type        = string
  default     = "~/.ssh/vockey.pem"
}
