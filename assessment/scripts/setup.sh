#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Docker and Wazuh installation..."

# Check available memory
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
if [ $MEMORY_GB -lt 3 ]; then
    echo "Warning: Insufficient memory for Wazuh. Minimum 4GB recommended, found ${MEMORY_GB}GB"
fi

# Update system
yum update -y || { echo "Failed to update system"; exit 1; }

# Install Docker
yum install -y docker || { echo "Failed to install Docker"; exit 1; }
systemctl start docker || { echo "Failed to start Docker"; exit 1; }
systemctl enable docker || { echo "Failed to enable Docker"; exit 1; }
usermod -a -G docker ec2-user || { echo "Failed to add user to docker group"; exit 1; }

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "Failed to download Docker Compose"; exit 1; }
chmod +x /usr/local/bin/docker-compose || { echo "Failed to make Docker Compose executable"; exit 1; }
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || { echo "Failed to create symlink"; exit 1; }

# Verify installations
docker --version || { echo "Docker verification failed"; exit 1; }
docker-compose --version || { echo "Docker Compose verification failed"; exit 1; }

# Deploy Wazuh
echo "Deploying Wazuh..."
WAZUH_DIR="/opt/wazuh"
mkdir -p $WAZUH_DIR
cd $WAZUH_DIR

# Create simplified docker-compose.yml for Wazuh
cat > docker-compose.yml << 'EOF'
version: '3.7'
services:
  wazuh.manager:
    image: wazuh/wazuh-manager:4.7.3
    hostname: wazuh.manager
    restart: always
    ports:
      - "1514:1514/udp"
      - "1515:1515"
      - "514:514/udp"
      - "55000:55000"
    environment:
      - INDEXER_URL=https://wazuh.indexer:9200
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=SecretPassword
      - FILEBEAT_SSL_VERIFICATION_MODE=full
      - SSL_CERTIFICATE_AUTHORITIES=/etc/ssl/root-ca.pem
      - SSL_CERTIFICATE=/etc/ssl/filebeat.pem
      - SSL_KEY=/etc/ssl/filebeat.key
      - API_USERNAME=wazuh-wui
      - API_PASSWORD=MyS3cr37P450r.*-
    volumes:
      - wazuh_api_configuration:/var/ossec/api/configuration
      - wazuh_etc:/var/ossec/etc
      - wazuh_logs:/var/ossec/logs
      - wazuh_queue:/var/ossec/queue
      - wazuh_var_multigroups:/var/ossec/var/multigroups
      - wazuh_integrations:/var/ossec/integrations
      - wazuh_active_response:/var/ossec/active-response/bin
      - wazuh_agentless:/var/ossec/agentless
      - wazuh_wodles:/var/ossec/wodles
      - filebeat_etc:/etc/filebeat
      - filebeat_var:/var/lib/filebeat
    depends_on:
      - wazuh.indexer
    networks:
      - wazuh

  wazuh.indexer:
    image: wazuh/wazuh-indexer:4.7.3
    hostname: wazuh.indexer
    restart: always
    ports:
      - "9200:9200"
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
      - "bootstrap.memory_lock=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - wazuh-indexer-data:/var/lib/wazuh-indexer
    networks:
      - wazuh

  wazuh.dashboard:
    image: wazuh/wazuh-dashboard:4.7.3
    hostname: wazuh.dashboard
    restart: always
    ports:
      - "443:5601"
    environment:
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=SecretPassword
      - WAZUH_API_URL=https://wazuh.manager
      - DASHBOARD_USERNAME=kibanaserver
      - DASHBOARD_PASSWORD=kibanaserver
      - API_USERNAME=wazuh-wui
      - API_PASSWORD=MyS3cr37P450r.*-
    volumes:
      - wazuh_dashboard_config:/usr/share/wazuh-dashboard/data/wazuh/config
      - wazuh_dashboard_custom:/usr/share/wazuh-dashboard/plugins/wazuh/public/assets/custom
    depends_on:
      - wazuh.indexer
    links:
      - wazuh.indexer:wazuh.indexer
      - wazuh.manager:wazuh.manager
    networks:
      - wazuh

volumes:
  wazuh_api_configuration:
  wazuh_etc:
  wazuh_logs:
  wazuh_queue:
  wazuh_var_multigroups:
  wazuh_integrations:
  wazuh_active_response:
  wazuh_agentless:
  wazuh_wodles:
  filebeat_etc:
  filebeat_var:
  wazuh-indexer-data:
  wazuh_dashboard_config:
  wazuh_dashboard_custom:

networks:
  wazuh:
    driver: bridge
EOF

# Start Wazuh stack
docker-compose up -d || { echo "Failed to start Wazuh stack"; exit 1; }

# Wait for services to start
echo "