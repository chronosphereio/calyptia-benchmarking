#!/bin/sh
set -eu

sudo sh <<SCRIPT
export DEBIAN_FRONTEND=noninteractive

curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
rm -f add-google-cloud-ops-agent-repo.sh

systemctl daemon-reload
systemctl enable google-cloud-ops-agent

SCRIPT

# https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent/troubleshooting#rotate-self-logs
sudo tee /etc/logrotate.d/google-cloud-ops-agent.conf > /dev/null << EOF
# logrotate config to rotate Google Cloud Ops Agent self log file.
/var/log/google-cloud-ops-agent/subagents/logging-module.log
{
    # Log files are rotated every day.
    daily
    # Log files are rotated this many times before being removed. This
    # effectively limits the disk space used by the Ops Agent self log files.
    rotate 30
    # Log files are rotated when they grow bigger than maxsize even before the
    # additionally specified time interval
    maxsize 256M
    # Skip rotation if the log file is missing.
    missingok
    # Do not rotate the log if it is empty.
    notifempty
    # Old versions of log files are compressed with gzip by default.
    compress
    # Postpone compression of the previous log file to the next rotation
    # cycle.
    delaycompress
}
EOF
