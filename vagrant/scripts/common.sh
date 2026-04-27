#!/bin/bash

# Update system
apt-get update -y

# Install basic tools
apt-get install -y curl wget net-tools

# Disable swap (important for Kubernetes later)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Set hostname in hosts file
echo "192.168.56.10 controller-1" >> /etc/hosts
echo "192.168.56.11 worker-1" >> /etc/hosts

# Enable IP forwarding (important later)
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p