#!/bin/bash
set -ex
exec > /var/log/kv-user-data.log 2>&1

# ── Install Docker ────────────────────────────────────────────────────────────
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# ── ECR Login & Pull ─────────────────────────────────────────────────────────
for i in $(seq 1 30); do
  aws ecr get-login-password --region ${aws_region} \
    | docker login --username AWS --password-stdin ${ecr_registry} && break
  echo "ECR login attempt $i failed, retrying in 5s..."
  sleep 5
done

for i in $(seq 1 60); do
  docker pull ${image} && break
  echo "docker pull attempt $i failed, retrying in 10s..."
  sleep 10
done

# Container will be started by Terraform null_resource after all node IPs are known.
echo "Base setup complete. Waiting for container start via provisioner." > /tmp/kv-setup-complete.txt
