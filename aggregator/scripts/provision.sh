#!/bin/bash
set -eux
export DEBIAN_FRONTEND=noninteractive

# Output mount points and partitions for debug later
df -h

# Temporarily disable automatic upgrades as locks can interfere during provisioning
systemctl stop apt-daily.timer
systemctl stop apt-daily-upgrade.timer
systemctl stop unattended-upgrades.service

## Monitoring stack

# Set up Docker repo
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

# Add any tools we need/want
apt-get update
apt-get upgrade -y
apt-get -y install apt-transport-https atop ca-certificates curl gpg lsb-release sudo \
    docker-ce docker-ce-cli containerd.io docker-compose-plugin jq net-tools

# Set up docker
systemctl daemon-reload
systemctl enable docker
if ! groupadd docker; then
    echo "docker group already exists"
fi
usermod -aG docker ubuntu

# Node exporter
mkdir -p /opt/node_exporter
curl -sSfL https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz | tar -C /opt/node_exporter --strip-components 1 -xz
cat > /etc/systemd/system/node-exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/node_exporter/node_exporter

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable node-exporter

# Process exporter
curl -o /tmp/process_exporter.deb -sSfL https://github.com/ncabatoff/process-exporter/releases/download/v0.7.10/process-exporter_0.7.10_linux_amd64.deb
apt-get install -y /tmp/process_exporter.deb
rm -f /tmp/process_exporter.deb

systemctl daemon-reload
systemctl enable process-exporter

# Now add Fluent Bit to scrape everything and send to Grafana Cloud easily:
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

# Pick up aggregator name
sed -i '/^ExecStart=.*/a EnvironmentFile=-/etc/profile.d/calyptia-core-config.sh' /lib/systemd/system/fluent-bit.service
# Add support for loading our environment file with any custom variables (e.g. Grafana Cloud tokens)
sed -i '/^ExecStart=.*/a EnvironmentFile=-/etc/fluent-bit/custom.env' /lib/systemd/system/fluent-bit.service

# Reload config and ensure we start it
systemctl daemon-reload
systemctl enable fluent-bit

## FluentD
curl -fsSL https://calyptia-fluentd.s3.us-east-2.amazonaws.com/calyptia-fluentd-1-ubuntu-focal.sh | sh
systemctl daemon-reload
systemctl disable calyptia-fluentd
# Use the /test/current config by default so we just push/update there
sed -i 's|Environment=FLUENT_CONF=.*|Environment=FLUENT_CONF=/test/current/fluentd.conf|g' /lib/systemd/system/calyptia-fluentd.service

# Ensure we have all the directories we need for copying
declare -a DIRS_TO_OWN=("/config"
                        "/etc/fluent-bit"
                        "/opt"
                        "/test"
                        "/test/current/")

for DIR in "${DIRS_TO_OWN[@]}"; do
    mkdir -p "${DIR}"
    chown -R ubuntu:ubuntu "${DIR}"
    chmod -R a+r "${DIR}"
done

apt-get autoremove -y
apt-get clean -y
