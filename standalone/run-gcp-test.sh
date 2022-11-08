#!/bin/bash
set -eu

# Not perfect but simple test for MacOS and other strangeness
# shellcheck disable=SC2016
if [ -z "$($SHELL -c 'echo $BASH_VERSION')" ]; then
    echo "Not detected Bash shell so may behave in unexpected ways"
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Pick up any configuration to apply locally, e.g. Grafana Cloud credentials
if [[ -f "$SCRIPT_DIR"/.env ]]; then
    echo "Loading local configuration overrides"
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR"/.env
    set +a
fi

VM_NAME=${VM_NAME:-vendor-comparison-test}
IMAGE_NAME=${IMAGE_NAME:-https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004}
MACHINE_TYPE=${MACHINE_TYPE:-e2-highcpu-32}
SSH_USERNAME=${SSH_USERNAME:-ubuntu}
GCP_PROJECT=${GCP_PROJECT:-calyptia-benchmark}

# Test options
OUTPUT_DIR=${OUTPUT_DIR:-$PWD/output}
RUN_TIMEOUT_MINUTES=${RUN_TIMEOUT_MINUTES:-5}
TEST_SCENARIO=${TEST_SCENARIO:-tail_null}
DISABLE_LOGSTASH=${DISABLE_LOGSTASH:-no}
DISABLE_STANZA=${DISABLE_STANZA:-no}
DISABLE_VECTOR=${DISABLE_VECTOR:-no}
DISABLE_CALYPTIA_LTS=${DISABLE_CALYPTIA_LTS:-no}

# Data generator options
export INPUT_LOG_RATE=${INPUT_LOG_RATE:-20000}
export INPUT_LOG_SIZE=${INPUT_LOG_SIZE:-1000}

echo "Running test scenario $TEST_SCENARIO at rate $INPUT_LOG_RATE with size: $INPUT_LOG_SIZE"

if gcloud compute instances delete "$VM_NAME" --project="$GCP_PROJECT" -q &> /dev/null ; then
    echo "Deleted existing $VM_NAME"
fi

echo "Creating new instance of $VM_NAME"
gcloud compute instances create "$VM_NAME" \
    --image="$IMAGE_NAME" \
    --machine-type="$MACHINE_TYPE" \
    --project="$GCP_PROJECT"

rm -rf "${OUTPUT_DIR:?}"/
mkdir -p "$OUTPUT_DIR"

# You must sleep for some initial VM deployment to appear otherwise terrible failures occur!
sleep 30

echo "Waiting for SSH access to $VM_NAME..."
until gcloud compute ssh --force-key-file-overwrite "$SSH_USERNAME"@"$VM_NAME" -q --command="true" --project="$GCP_PROJECT" 2> /dev/null; do
    echo -n '.'
    sleep 1
done
echo
echo "Successfully connected to $VM_NAME"

echo "To port-forward (e.g. Grafana and Prometheus): gcloud compute ssh --project=$GCP_PROJECT $SSH_USERNAME@$VM_NAME -- -NL 3000:localhost:3000 -- -NL 9090:localhost:9090"

if [[ "${TRANSFER_UPDATED_FRAMEWORK:-no}" != "no" ]]; then
    echo "Updating remote test framework with local files"
    gcloud compute scp --recurse ./config/test/* "$SSH_USERNAME"@"$VM_NAME":/test --project="$GCP_PROJECT"
fi

# If we have set any Grafana Cloud credentials then assume we want to forward to it from the VM Prometheus
# https://grafana.com/docs/grafana-cloud/data-configuration/metrics/metrics-prometheus/
if [[ -n "${GRAFANA_CLOUD_PROM_URL:-}" ]]; then
    # Handle FB config with just the start of the URL
    if [[ ${GRAFANA_CLOUD_PROM_URL} != https* ]]; then
        GRAFANA_CLOUD_PROM_URL="https://${GRAFANA_CLOUD_PROM_URL:?}/api/prom/push"
    fi
    echo "Setting up Grafana Cloud remote write to $GRAFANA_CLOUD_PROM_URL"
    PROM_CFG_YAML=$(mktemp)
    cp -fv "$SCRIPT_DIR"/config/monitoring/prometheus/prometheus.yml.tmpl "$PROM_CFG_YAML"
    cat >> "$PROM_CFG_YAML" << GC_EOF

remote_write:
- url: ${GRAFANA_CLOUD_PROM_URL:?}
  basic_auth:
    username: ${GRAFANA_CLOUD_PROM_USERNAME:?}
    password: ${GRAFANA_CLOUD_APIKEY:?}
GC_EOF
    cat "$PROM_CFG_YAML"
    gcloud compute scp "$PROM_CFG_YAML" "$SSH_USERNAME"@"$VM_NAME":/opt/fluent-bit-devtools/monitoring/prometheus/prometheus.yml.tmpl --project="$GCP_PROJECT"
    rm -f "$PROM_CFG_YAML"
fi

echo "Running test"
gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" --project="$GCP_PROJECT" --command "\
    export TEST_SCENARIO=$TEST_SCENARIO;\
    export INPUT_LOG_RATE=$INPUT_LOG_RATE;\
    export INPUT_LOG_SIZE=$INPUT_LOG_SIZE;\
    export RUN_TIMEOUT_MINUTES=$RUN_TIMEOUT_MINUTES;\
    export OUTPUT_DIR=/tmp/output;\
    export DISABLE_LOGSTASH=${DISABLE_LOGSTASH};\
    export DISABLE_STANZA=${DISABLE_STANZA};\
    export DISABLE_VECTOR=${DISABLE_VECTOR};\
    export DISABLE_CALYPTIA_LTS=${DISABLE_CALYPTIA_LTS};\
    /test/run-test.sh"

if [[ $RUN_TIMEOUT_MINUTES -gt 0 ]]; then
    echo "Transferring output files to $OUTPUT_DIR"
    gcloud compute scp --recurse "$SSH_USERNAME"@"$VM_NAME":/tmp/output/* "$OUTPUT_DIR" --project="$GCP_PROJECT"

    if [[ "${SKIP_TEARDOWN:-no}" != "no" ]]; then
        echo "Leaving instance running"
    else
        echo "Destroying instance"
        gcloud compute instances delete "$VM_NAME" -q --project="$GCP_PROJECT"
    fi
else
    echo "Left $VM_NAME running for continuous test"
fi

echo "Completed test scenario $TEST_SCENARIO at rate $INPUT_LOG_RATE with size: $INPUT_LOG_SIZE"
