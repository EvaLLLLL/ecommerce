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

# ── Start KV Database Container ──────────────────────────────────────────────
docker run -d --name kv-node --restart unless-stopped \
  -p ${port}:${port} \
  -e KV_DATABASE_PORT=${port} \
  -e ROLE=${role} \
%{ if follower_urls != "" ~}
  -e FOLLOWER_URLS='${follower_urls}' \
%{ endif ~}
%{ if write_quorum > 0 ~}
  -e WRITE_QUORUM_SIZE=${write_quorum} \
%{ endif ~}
%{ if read_quorum > 0 ~}
  -e READ_QUORUM_SIZE=${read_quorum} \
%{ endif ~}
  ${image}

echo "KV node started (role=${role}, port=${port})" > /tmp/kv-setup-complete.txt
