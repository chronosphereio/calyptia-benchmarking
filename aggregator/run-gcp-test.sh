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

INPUT_VM_NAME_PREFIX=${INPUT_VM_NAME_PREFIX:-benchmark-instance-input}
INPUT_IMAGE_NAME=${INPUT_IMAGE_NAME:-https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004}
INPUT_MACHINE_TYPE=${INPUT_MACHINE_TYPE:-e2-highcpu-8}
INPUT_VM_COUNT=${INPUT_VM_COUNT:-3}
export INPUT_LOG_RATE=${INPUT_LOG_RATE:-20000}
export INPUT_LOG_SIZE=${INPUT_LOG_SIZE:-1000}

SSH_USERNAME=${SSH_USERNAME:-ubuntu}

CORE_VM_NAME=${CORE_VM_NAME:-benchmark-instance-core}
# This should be the latest public image for the region you want to use
CORE_IMAGE_NAME=${CORE_IMAGE_NAME:-https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-core-benchmark-ubuntu-2004}
CORE_MACHINE_TYPE=${CORE_MACHINE_TYPE:-e2-highcpu-16}
export CORE_PORT=${CORE_PORT:-5000}
CALYPTIA_CLOUD_PROJECT_TOKEN=${CALYPTIA_CLOUD_PROJECT_TOKEN:?}
CALYPTIA_CLOUD_AGGREGATOR_NAME=${CALYPTIA_CLOUD_AGGREGATOR_NAME:-}

# Where all the tests are stored
TEST_ROOT=${TEST_ROOT:-$SCRIPT_DIR/test}
# One of the configuration scenarios to run
TEST_SCENARIO=${TEST_SCENARIO:-tcp_input}
TEST_SCENARIO_DIR=${TEST_SCENARIO_DIR:-$TEST_ROOT/scenarios/$TEST_SCENARIO}
# Where to store configuration files post processing
TEST_CONFIG_TMP_DIR=${TEST_CONFIG_TMP_DIR:-$(mktemp -d)}

# Indicate which aggregator to test: mutually exclusive
ENABLE_CORE=${ENABLE_CORE:-yes}
ENABLE_FLUENTD=${ENABLE_FLUENTD:-no}

function cleanup() {
    for index in $(seq "$INPUT_VM_COUNT")
    do
        VM_NAME="${INPUT_VM_NAME_PREFIX}-$index"
        gcloud compute instances delete "$VM_NAME" -q &> /dev/null || true
    done

    gcloud compute instances delete "$CORE_VM_NAME" -q &> /dev/null || true
}

function wait_for_ssh() {
    local VM_NAME=$1
    echo "Waiting for SSH access to $VM_NAME..."
    until gcloud compute ssh --force-key-file-overwrite "$SSH_USERNAME"@"$VM_NAME" -q --command="true" 2> /dev/null; do
        echo -n '.'
        sleep 1
    done
    echo
    echo "Successfully connected to $VM_NAME"
}

function validate_config() {
    if [[ ! -d "$TEST_ROOT" ]]; then
        echo "ERROR: Invalid TEST_ROOT directory: $TEST_ROOT"
        exit 1
    fi

    if [[ ! -d "$TEST_SCENARIO_DIR" ]]; then
        echo "ERROR: Invalid TEST_SCENARIO_DIR directory: $TEST_SCENARIO_DIR"
        exit 1
    fi

    if [[ "${ENABLE_CORE}" == "yes" ]]; then
        echo "Enabled Calyptia Core"
    elif [[ "${ENABLE_FLUENTD}" != "no" ]]; then
        echo "Enabled Fluentd"
    else
        echo "ERROR: No aggregators configured"
        exit 1
    fi
}

function setup_aggregator_base() {
    # Sets up all common test files and fluent bit on the aggregator VM
    local VM_NAME=$1
    wait_for_ssh "$VM_NAME"
    # Set up pushing metrics and logs to Grafana Cloud
    gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="sudo systemctl stop fluent-bit; \
        echo GRAFANA_CLOUD_PROM_URL=${GRAFANA_CLOUD_PROM_URL:?} >> /etc/fluent-bit/custom.env; \
        echo GRAFANA_CLOUD_PROM_USERNAME=${GRAFANA_CLOUD_PROM_USERNAME:?} >> /etc/fluent-bit/custom.env; \
        echo GRAFANA_CLOUD_APIKEY=${GRAFANA_CLOUD_APIKEY:?} >> /etc/fluent-bit/custom.env; \
        echo GRAFANA_CLOUD_LOKI_URL=${GRAFANA_CLOUD_LOKI_URL:?} >> /etc/fluent-bit/custom.env; \
        echo GRAFANA_CLOUD_LOKI_USERNAME=${GRAFANA_CLOUD_LOKI_USERNAME:?} >> /etc/fluent-bit/custom.env; \
        cat /etc/fluent-bit/custom.env; \
        sudo systemctl daemon-reload; \
        sudo systemctl reset-failed fluent-bit; \
        sudo systemctl start fluent-bit"

    echo "Setting up Core instance"
    mkdir -p "$TEST_CONFIG_TMP_DIR"
    rm -rf "${TEST_CONFIG_TMP_DIR:?}"/*
    for CONFIG_FILE in "$TEST_SCENARIO_DIR"/*.conf; do
        OUTPUT_FILE="$TEST_CONFIG_TMP_DIR"/$(basename "$CONFIG_FILE")
        # shellcheck disable=SC2016
        envsubst '$INPUT_LOG_RATE,$INPUT_LOG_SIZE,$CORE_PORT,$GRAFANA_CLOUD_PROM_URL,$GRAFANA_CLOUD_PROM_USERNAME,$GRAFANA_CLOUD_APIKEY,$GRAFANA_CLOUD_LOKI_URL,$GRAFANA_CLOUD_LOKI_USERNAME' \
            < "$CONFIG_FILE" > "$OUTPUT_FILE"
    done
    # Services should use /test/current as default configuration
    gcloud compute scp --recurse "$TEST_CONFIG_TMP_DIR"/* "$SSH_USERNAME"@"$VM_NAME":/test/current/

    # Turn everything off in case this is run on existing VMs
    gcloud compute ssh "$SSH_USERNAME"@"$CORE_VM_NAME" -q --command="calyptia delete pipeline --token \"$CALYPTIA_CLOUD_PROJECT_TOKEN\" benchmark-test --yes || true;"
    gcloud compute ssh "$SSH_USERNAME"@"$CORE_VM_NAME" -q --command="sudo systemctl stop calyptia-fluentd"
}

function setup_core_vm() {
    local CORE_VM_NAME=$1
    setup_aggregator_base "$CORE_VM_NAME"
    echo "Enabling Calyptia Core on $CORE_VM_NAME"
    gcloud compute ssh "$SSH_USERNAME"@"$CORE_VM_NAME" -q --command="set -x; \
        calyptia delete pipeline --token \"$CALYPTIA_CLOUD_PROJECT_TOKEN\" benchmark-test --yes || true; \
        source /etc/profile.d/calyptia-core-config.sh; \
        calyptia create pipeline --token \"$CALYPTIA_CLOUD_PROJECT_TOKEN\" \
            --aggregator \"\$CALYPTIA_CLOUD_AGGREGATOR_NAME\" --name benchmark-test --config-file /test/current/core.conf"
}

function setup_fluentd_core_vm() {
    local CORE_VM_NAME=$1
    setup_aggregator_base "$CORE_VM_NAME"

    echo "Enabling Fluentd on $CORE_VM_NAME"
    gcloud compute ssh "$SSH_USERNAME"@"$CORE_VM_NAME" -q --command="sudo systemctl restart calyptia-fluentd"
}

function create_input_to_core_config() {
    # We need the IP address to add to the config files for inputs
    CORE_HOST="$(gcloud compute instances describe "$CORE_VM_NAME" --format='get(networkInterfaces[0].networkIP)')"
    export CORE_HOST

    echo "Setting up input instances"
    # shellcheck disable=SC2016
    envsubst '$CORE_PORT,$CORE_HOST' < "$TEST_SCENARIO_DIR"/fluent-bit.conf > "$TEST_ROOT"/benchmark-output.conf
}

function setup_input_vm() {
    # Start data generation
    gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="export INPUT_LOG_RATE=$INPUT_LOG_RATE; export INPUT_LOG_SIZE=$INPUT_LOG_SIZE; \
        /test/scenarios/tail_null/data_generator/stop.sh; nohup /test/scenarios/tail_null/data_generator/run.sh &"
    # Ensure we send the data using Calyptia LTS Fluent Bit to the core VM
    gcloud compute scp "$TEST_ROOT/"benchmark-output.conf "$SSH_USERNAME"@"$VM_NAME":/etc/calyptia-fluent-bit/custom/
    gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="rm -f /etc/calyptia-fluent-bit/custom/null.conf; \
        sudo systemctl restart calyptia-fluent-bit"

    if [[ "${RUN_INPUT_MONITORING_STACK:-no}" != "no" ]]; then
        echo "Running instance monitoring stack"
        gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="cd /opt/fluent-bit-devtools/monitoring && docker compose up --force-recreate --always-recreate-deps -d"
        echo "To port-forward (e.g. Grafana and Prometheus): gcloud compute ssh $SSH_USERNAME@$VM_NAME -- -NL 3000:localhost:3000 -- -NL 9090:localhost:9090"
    fi
}

function send_grafana_annotation() {
    if [[ -n "${GRAFANA_ANNOTATION_APIKEY:-}" ]]; then
        local annotation_text="Start of benchmark for $TEST_SCENARIO, INPUT_MACHINE_TYPE=${INPUT_MACHINE_TYPE}, INPUT_VM_COUNT=${INPUT_VM_COUNT}, INPUT_LOG_RATE=${INPUT_LOG_RATE}, INPUT_LOG_SIZE=${INPUT_LOG_SIZE}, CORE_MACHINE_TYPE=${CORE_MACHINE_TYPE}"
        curl \
            -H "Authorization: Bearer ${GRAFANA_ANNOTATION_APIKEY:?}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "{ \"tags\": [ \"$TEST_SCENARIO\" ], \"text\" : \"$annotation_text\", \"dashboardUid\" : \"${GRAFANA_DASHBOARD_UID:-uCkUSPiVz}\" }" \
            "${GRAFANA_HOST:-https://calyptiabenchmarks.grafana.net}"/api/annotations
    else
        echo "No GRAFANA_ANNOTATION_APIKEY specified so skipping creating annotation"
    fi
}

validate_config

if [[ "${SKIP_VM_CREATION:-no}" == "no" ]]; then
    echo "Creating $INPUT_VM_COUNT input instances"
    for index in $(seq "$INPUT_VM_COUNT")
    do
        VM_NAME="${INPUT_VM_NAME_PREFIX}-$index"
        gcloud compute instances delete "$VM_NAME" -q &> /dev/null || true
        gcloud compute instances create "$VM_NAME" \
            --image="$INPUT_IMAGE_NAME" \
            --machine-type="$INPUT_MACHINE_TYPE"
    done

    echo "Creating Core instance"
    gcloud compute instances delete "$CORE_VM_NAME" -q &> /dev/null || true
    gcloud compute instances create "$CORE_VM_NAME" \
        --image="$CORE_IMAGE_NAME" \
        --machine-type="$CORE_MACHINE_TYPE" \
        --metadata=CALYPTIA_CLOUD_PROJECT_TOKEN="$CALYPTIA_CLOUD_PROJECT_TOKEN",CALYPTIA_CLOUD_AGGREGATOR_NAME="$CALYPTIA_CLOUD_AGGREGATOR_NAME"
    wait_for_ssh "$CORE_VM_NAME"
fi

send_grafana_annotation

# Now we can enable one of the aggregators we want to test
if [[ "${ENABLE_CORE}" == "yes" ]]; then
    setup_core_vm "$CORE_VM_NAME"
    echo "Enabled Calyptia Core"
elif [[ "${ENABLE_FLUENTD}" != "no" ]]; then
    setup_fluentd_core_vm "$CORE_VM_NAME"
    echo "Enabled Fluentd"
fi

# Finally enable the sending of the data from input VMs to core VM
create_input_to_core_config

for index in $(seq "$INPUT_VM_COUNT")
do
    VM_NAME="benchmark-instance-input-$index"
    wait_for_ssh "$VM_NAME"
    setup_input_vm "$VM_NAME"
done

echo "Setup completed and running"
