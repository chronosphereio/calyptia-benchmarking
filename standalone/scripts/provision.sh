#!/bin/bash
set -eux

# Configuration here
CALYPTIA_LTS_VERSION=${CALYPTIA_LTS_VERSION:-22.4.4}
CALYPTIA_PACKAGES_URL=${CALYPTIA_PACKAGES_URL:-https://calyptia-lts-staging-standard.s3.amazonaws.com/linux/$CALYPTIA_LTS_VERSION}
CALYPTIA_PACKAGES_KEY=${CALYPTIA_PACKAGES_KEY:-$CALYPTIA_PACKAGES_URL/calyptia.key}

# Add supporting software
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install apt-transport-https atop ca-certificates curl gpg lsb-release smem sudo
# Do not upgrade as triggers connection problems
# apt-get -y upgrade

# Handle test data log rotation every 5 minutes
cp -fv /tmp/logrotate-test.* /lib/systemd/system/
systemctl daemon-reload
systemctl enable logrotate-test.timer

# Set high limits for FD usage
cat > /etc/security/limits.d/benchmarking.conf << EOF
# Setting unlimited FD usage for benchmarking purposes
#
* hard nofile unlimited
* soft nofile unlimited
* hard nproc unlimited
* soft nproc unlimited
EOF

## Monitoring stack

# Set up Docker repo
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

# Install httpie
curl -fsSL https://packages.httpie.io/deb/KEY.gpg | gpg --dearmor -o /etc/apt/keyrings/httpie.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/httpie.gpg] https://packages.httpie.io/deb ./" | tee /etc/apt/sources.list.d/httpie.list

# Add any tools we need
apt-get update
apt-get -y install docker-ce \
                    docker-ce-cli \
                    containerd.io \
                    docker-compose-plugin \
                    git \
                    iperf3 \
                    jq \
                    httpie \
                    mz \
                    netsniff-ng \
                    net-tools \
                    nmap \
                    parallel \
                    python3 \
                    syslog-ng-core \
                    tcpreplay
systemctl daemon-reload
systemctl enable docker
if ! groupadd docker; then
    echo "docker group already exists"
fi
usermod -aG docker ubuntu

# Add promplot
mkdir -p /opt/promplot
curl -fsSL https://github.com/qvl/promplot/releases/download/v0.17.0/promplot_0.17.0_linux_64bit.tar.gz| tar -xz -C /opt/promplot
chmod a+x /opt/promplot/promplot
cp -vf /opt/promplot/promplot /usr/local/bin/promplot

# Clone monitoring stack from dev tools
git -C /opt clone https://github.com/calyptia/fluent-bit-devtools.git
# Clone CI to get the snapshot loader
git -C /opt clone https://github.com/fluent/fluent-bit-ci.git
# Clone the benchmark server as well just in case
git -C /opt clone https://github.com/calyptia/https-benchmark-server.git
# Clone the BATS repo with common methods, etc. for tests
git -C /opt clone https://github.com/calyptia/bats.git

cat > /etc/profile.d/10-devtools.sh << EOF
#!/bin/sh
export DEV_TOOLS_REPO_DIR=/opt/fluent-bit-devtools
export MONITORING_STACK_DIR=/opt/fluent-bit-devtools/monitoring

export FLUENT_BIT_CI_REPO_DIR=/opt/fluent-bit-ci
export HTTPS_BENCHMARK_SERVER_REPO_DIR=/opt/https-benchmark-server
export BATS_REPO_DIR=/opt/bats
EOF

## LTS
# Taken from https://github.com/calyptia/calyptia-fluent-bit/blob/main/scripts/install-package.sh

echo "Installing Calyptia Fluent Bit LTS: ${CALYPTIA_LTS_VERSION}"

# Set up GPG and repositories
curl -fsSL "$CALYPTIA_PACKAGES_KEY" | gpg --dearmor -o /etc/apt/keyrings/calyptia-keyring.gpg
cat > /etc/apt/sources.list.d/calyptia.list <<EOF
deb [signed-by=/etc/apt/keyrings/calyptia-keyring.gpg] $CALYPTIA_PACKAGES_URL/package-ubuntu-20.04/ 20.04 main
EOF
cat /etc/apt/sources.list.d/calyptia.list

# Now install LTS - be aware of configuration overwrite
apt-get update
apt-get -y install calyptia-fluent-bit

# Ensure system is configured to autostart LTS with environment values
mkdir -p /etc/systemd/system/calyptia-fluent-bit.service.d/
cat > /etc/systemd/system/calyptia-fluent-bit.service.d/local.conf <<EOF
[Service]
Environment="CALYPTIA_LTS_VERSION=$CALYPTIA_LTS_VERSION"
LimitNOFILE=infinity
LimitNPROC=infinity
EOF

cat > /etc/profile.d/10-calyptia.sh << EOF
#!/bin/sh
export CALYPTIA_LTS_VERSION=$CALYPTIA_LTS_VERSION
EOF

# Reload config and ensure we do not start it
systemctl daemon-reload
systemctl stop calyptia-fluent-bit
systemctl disable calyptia-fluent-bit

# Allow anyone to make custom config here
mkdir -p /etc/calyptia-fluent-bit/custom/
chmod -R a+w /etc/calyptia-fluent-bit/

## OSS Fluent Bit
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

# Ensure system is configured to have unlimited limits
mkdir -p /etc/systemd/system/fluent-bit.service.d/
cat > /etc/systemd/system/fluent-bit.service.d/local.conf <<EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
EOF

# Reload config and ensure we do not start it
systemctl daemon-reload
systemctl stop fluent-bit
systemctl disable fluent-bit

## Vector
curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | bash
apt-get update
apt-get -y install vector
# We do not want extra users for vector so remove
sed -i '/User=vector/d' /lib/systemd/system/vector.service
sed -i '/Group=vector/d' /lib/systemd/system/vector.service

systemctl daemon-reload
systemctl stop vector
systemctl disable vector

## Logstash
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /etc/apt/keyrings/elastic.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-8.x.list
apt-get update
apt-get -y install logstash
# We do not want extra users for logstash so remove
sed -i '/User=logstash/d' /lib/systemd/system/logstash.service
sed -i '/Group=logstash/d' /lib/systemd/system/logstash.service

systemctl daemon-reload
systemctl stop logstash.service
systemctl disable logstash.service

## Stanza
curl -fsSL -o /tmp/stanza.deb https://github.com/observIQ/stanza/releases/download/v1.6.2/stanza_1.6.2_linux_amd64.deb
apt-get install -f /tmp/stanza.deb
rm -f /tmp/stanza.deb

# We do not want extra users for stanza so remove
sed -i '/User=stanza/d' /lib/systemd/system/stanza.service
sed -i '/Group=stanza/d' /lib/systemd/system/stanza.service
# Pick up output as well
sed -i '/StandardOutput=null/d' /lib/systemd/system/stanza.service

systemctl daemon-reload
systemctl stop stanza
systemctl disable stanza

# Ensure we have all the directories we need for copying
declare -a DIRS_TO_OWN=("/etc/calyptia-fluent-bit"
                        "/etc/fluent-bit"
                        "/etc/logstash"
                        "/etc/vector"
                        "/opt/observiq/stanza"
                        "/test"
                        "/opt")

for DIR in "${DIRS_TO_OWN[@]}"; do
    mkdir -p "${DIR}"
    chown -R ubuntu:ubuntu "${DIR}"
    chmod -R a+r "${DIR}"
done
