#!/bin/bash
set -eux
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

PORT=${PORT:-514}
MONITORING_STACK_DIR=${MONITORING_STACK_DIR:-/opt/fluent-bit-devtools/monitoring}

sudo sh -x << EOF
systemctl stop fluent-bit
systemctl stop rsyslog
systemctl disable rsyslog

apt-get update
apt-get install -y mz netsniff-ng net-tools nmap syslog-ng-core tcpreplay

usermod -aG docker "$USER"

cp -fv /etc/fluent-bit/fluent-bit.conf /etc/fluent-bit/fluent-bit.conf.orig
cp -fv "$SCRIPT_DIR"/fluent-bit/* /etc/fluent-bit/
systemctl daemon-reload
systemctl enable --now fluent-bit

mkdir -p /etc/systemd/system/ /opt/syslog-sender
cp -fv "$SCRIPT_DIR"/*.service /etc/systemd/system/
cp -fv "$SCRIPT_DIR"/syslog-sender/* /opt/syslog-sender/
systemctl daemon-reload
systemctl enable --now syslog-sender

systemctl status fluent-bit syslog-sender

cp -Rfv "$SCRIPT_DIR"/monitoring/* "$MONITORING_STACK_DIR"/

cd "$MONITORING_STACK_DIR"
docker compose pull --include-deps --quiet
docker compose up --force-recreate --always-recreate-deps -d
EOF

echo "Confirm port is up"
nc -vz -u 127.0.0.1 "$PORT"
