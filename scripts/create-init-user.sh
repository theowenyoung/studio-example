#!/usr/bin/env bash
# 给服务器创建 deploy 用户
set -ex

DEPLOY_USER="deploy"
SSH_KEYS=(
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAPcRy9wGjP47bHpv2RcNO3yw3udCcTlgWs22KLcpUW main@example.com"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXuWwHvnngN6Hza3KopWE7i8XllW8V78MQwT6XBs/j6 deploy@example.com"
)

# 创建用户
useradd -m -s /bin/bash $DEPLOY_USER || echo "User exists"

# 配置 sudo
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/$DEPLOY_USER
chmod 440 /etc/sudoers.d/$DEPLOY_USER

# 设置 SSH 密钥
mkdir -p /home/$DEPLOY_USER/.ssh
printf "%s\n" "${SSH_KEYS[@]}" >/home/$DEPLOY_USER/.ssh/authorized_keys
chmod 700 /home/$DEPLOY_USER/.ssh
chmod 600 /home/$DEPLOY_USER/.ssh/authorized_keys
chown -R $DEPLOY_USER:$DEPLOY_USER /home/$DEPLOY_USER/.ssh

echo "✅ User $DEPLOY_USER created with SSH key and sudo access"
