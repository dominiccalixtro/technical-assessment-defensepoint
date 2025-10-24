#!/bin/bash
set -e

# Redirect all output to a log file
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting EC2 setup for Wazuh using official Docker Compose..."

# Short delay to ensure network is ready
sleep 10

# -----------------------------
# Update system
# -----------------------------
echo "Updating system packages..."
yum update -y || { echo "Failed to update system"; exit 1; }

# -----------------------------
# Install Docker
# -----------------------------
echo "Installing Docker..."
amazon-linux-extras enable docker || { echo "Failed to enable Docker extras"; exit 1; }
yum install -y docker || { echo "Failed to install Docker"; exit 1; }
systemctl enable --now docker || { echo "Failed to start/enable Docker"; exit 1; }
usermod -aG docker ec2-user || { echo "Failed to add ec2-user to Docker group"; exit 1; }

# -----------------------------
# Install Docker Compose
# -----------------------------
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "Failed to download Docker Compose"; exit 1; }
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# -----------------------------
# Verify Docker and Compose
# -----------------------------
echo "Verifying Docker and Docker Compose..."
/usr/bin/docker --version || { echo "Docker verification failed"; exit 1; }
/usr/local/bin/docker-compose --version || { echo "Docker Compose verification failed"; exit 1; }

# -----------------------------
# Deploy Wazuh (Official Docker Compose)
# -----------------------------
echo "Deploying Wazuh..."
WAZUH_DIR="/opt/wazuh"
mkdir -p $WAZUH_DIR
cd $WAZUH_DIR

# Download the official single-node Docker Compose file
curl -sL https://raw.githubusercontent.com/wazuh/wazuh-docker/main/single-node/docker-compose.yml -o docker-compose.yml || { echo "Failed to download official docker-compose.yml"; exit 1; }

# Set Wazuh version to a valid Docker Hub version
WAZUH_VERSION="4.8.0"

# Correctly replace image tags to Docker Hub images
sed -i "s|wazuh/wazuh-manager:.*|wazuh/wazuh-manager:$WAZUH_VERSION|g" docker-compose.yml
sed -i "s|wazuh/wazuh-indexer:.*|wazuh/wazuh-indexer:$WAZUH_VERSION|g" docker-compose.yml
sed -i "s|wazuh/wazuh-dashboard:.*|wazuh/wazuh-dashboard:$WAZUH_VERSION|g" docker-compose.yml

# Remove the problematic Dashboard config mount (opensearch_dashboards.yml)
sed -i '/opensearch_dashboards.yml/d' docker-compose.yml

# Start Wazuh stack
docker-compose up -d || { echo "Failed to start Wazuh stack"; exit 1; }

# -----------------------------
# Configure basic system logging
# -----------------------------
echo "Configuring system logging..."
systemctl enable rsyslog || { echo "Failed to enable rsyslog"; exit 1; }
systemctl start rsyslog || { echo "Failed to start rsyslog"; exit 1; }

echo "Wazuh deployment and system logging setup completed successfully."
