#!/bin/sh
set -eu

AWS_DIR=${AWS_DIR:-/opt/aws}
PROVISIONED_USER=${PROVISIONED_USER:-ubuntu}
PROVISIONED_GROUP=${PROVISIONED_GROUP:-$PROVISIONED_USER}

UNAME_ARCH=$(uname -m)
DPKG_ARCH=$(dpkg --print-architecture)

sudo sh <<SCRIPT
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ec2-instance-connect unzip

snap install amazon-ssm-agent --classic
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

# Provide the AWS CLI in case it is not present already
curl -sSfl -o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${UNAME_ARCH}.zip"
unzip /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws/ /tmp/awscliv2.zip

# Provide the Cloudwatch agent for monitoring
curl -sSfl -o /tmp/amazon-cloudwatch-agent.deb "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${DPKG_ARCH}/latest/amazon-cloudwatch-agent.deb"
dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
rm -f /tmp/amazon-cloudwatch-agent.deb

aws configure --profile AmazonCloudWatchAgent

systemctl enable amazon-cloudwatch-agent
chown -R $PROVISIONED_USER:$PROVISIONED_GROUP "$AWS_DIR"/
chmod -R a+r "$AWS_DIR"/

SCRIPT
