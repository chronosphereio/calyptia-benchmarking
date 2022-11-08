#!/bin/bash
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

VM_NAME=${VM_NAME:-fluent-bit-test-syslog}
IMAGE_NAME=${IMAGE_NAME:-https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004}
MACHINE_TYPE=${MACHINE_TYPE:-e2-highcpu-32}
GCP_PROJECT=${GCP_PROJECT:-calyptia-benchmark}

if [[ "${SKIP_VM_CREATION:-no}" == "no" ]]; then
    if gcloud compute instances delete "$VM_NAME" -q --project="$GCP_PROJECT" &> /dev/null ; then
        echo "Deleted existing instance"
    fi

    echo "Creating new $VM_NAME instance in $GCP_PROJECT"
    gcloud compute instances create "$VM_NAME" \
        --image="$IMAGE_NAME" \
        --machine-type="$MACHINE_TYPE" \
        --project="$GCP_PROJECT"

    echo "Waiting for connection"
    until gcloud compute ssh "$VM_NAME" --project="$GCP_PROJECT" -q --command="true" &> /dev/null ; do
        sleep 5
    done
fi

echo "Copying over set up files"
gcloud compute scp --recurse "$SCRIPT_DIR/syslog-test" "$VM_NAME:~/" --project="$GCP_PROJECT"

echo "Setting up VM to run tests"
gcloud compute ssh "$VM_NAME" --project="$GCP_PROJECT" --command="/bin/bash ~/syslog-test/provision.sh"
echo "Complete"

gcloud compute ssh "$VM_NAME" -q --command="curl -s http://127.0.0.1:2020/api/v1/metrics/prometheus"

echo "Port forwarding to Grafana and Prometheus: gcloud compute ssh $VM_NAME -- -NL 3000:localhost:3000 -- -NL 9090:localhost:9090"
echo "Go to http://localhost:3000/ now and log in as admin:admin"
gcloud compute ssh "$VM_NAME" -- -NL 3000:localhost:3000 -- -NL 9090:localhost:9090
