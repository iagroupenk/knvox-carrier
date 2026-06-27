#!/bin/bash
set -e

SSH_PORT="${SSH_PORT:-22}"

echo "===================================="
echo " KNVOX FIREWALL"
echo "===================================="
echo "SSH port autorisé : ${SSH_PORT}"
echo ""

apt-get update
apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable
ufw status numbered
