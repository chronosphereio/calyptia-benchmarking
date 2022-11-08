#!/bin/bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Set to 0 for continuous running
RUN_TIMEOUT_MINUTES=${RUN_TIMEOUT_MINUTES:-10}
# Location for any generated output
OUTPUT_DIR=${OUTPUT_DIR:-$PWD/output}

# The URL to hit for Prometheus from the host.
PROM_URL=${PROM_URL:-http://localhost:9090}
# The name of the service providing prometheus to trigger a snapshot on
PROM_SERVICE_NAME=${PROM_SERVICE_NAME:-prometheus}

# The Docker Compose stack with Prometheus, etc.
MONITORING_STACK_DIR=${MONITORING_STACK_DIR:-/opt/fluent-bit-devtools/monitoring}

# Where all the tests are stored
TEST_ROOT=${TEST_ROOT:-$SCRIPT_DIR}
# One of the configuration scenarios to run
TEST_SCENARIO=${TEST_SCENARIO:-tail_null}
TEST_SCENARIO_DIR=${TEST_SCENARIO_DIR:-$TEST_ROOT/scenarios/$TEST_SCENARIO}
# Data will be generated and/or consumed from here
TEST_SCENARIO_DATA_DIR=${TEST_SCENARIO_DATA_DIR:-/test/data}

# Disable components by setting true/yes.
# Note that additionally if a configuration does not have a directory for one of these then it is disabled too.
DISABLE_LOGSTASH=${DISABLE_LOGSTASH:-no}
DISABLE_STANZA=${DISABLE_STANZA:-no}
DISABLE_VECTOR=${DISABLE_VECTOR:-no}
DISABLE_CALYPTIA_LTS=${DISABLE_CALYPTIA_LTS:-no}

if [[ ! -d "$TEST_ROOT" ]]; then
    echo "Invalid TEST_ROOT directory: $TEST_ROOT"
    exit 1
fi

if [[ ! -d "$TEST_SCENARIO_DIR" ]]; then
    echo "Invalid TEST_SCENARIO_DIR directory: $TEST_SCENARIO_DIR"
    exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# Useful check we can run sudo plus also make sure we have container access
sudo usermod -aG docker "$USER"

echo "Start up monitoring stack - pull images"
run_monitoring_stack

echo "Start up comparison stack"
run_comparison

if [[ $RUN_TIMEOUT_MINUTES -gt 0 ]]; then
    echo "Monitoring started "
    END=$(( SECONDS+(60*RUN_TIMEOUT_MINUTES) ))
    # Check every 10 seconds that our service is still up
    # shellcheck disable=SC2086
    while [ $SECONDS -lt $END ]; do
        check_running
        sample_memory_cpu
        echo -n '.'
        sleep 10
    done
    echo
    
    echo "Dumping current memory usage"
    # shellcheck disable=SC2024
    sudo smem -kt > "$OUTPUT_DIR"/smem-end.txt

    echo "Monitoring ended"
    stop_comparison

    echo "Checking we have got the expected records (if any)"
    check_expected

    echo "Export metrics"
    prom_snapshot
    prom_query

    echo "Metric export ended"
    stop_monitoring_stack

    get_logs
    echo "Log export ended"
else
    echo "Continuous running as RUN_TIMEOUT_MINUTES <= 0"
fi