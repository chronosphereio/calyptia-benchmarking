#!/bin/bash
set -eu

# Not perfect but simple test for MacOS and other strangeness
# shellcheck disable=SC2016
if [ -z "$($SHELL -c 'echo $BASH_VERSION')" ]; then
    echo "Not detected Bash shell so may behave in unexpected ways"
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

INPUT_VM_NAME_PREFIX=${INPUT_VM_NAME_PREFIX:-benchmark-instance-standalone}
OUTPUT_BASE_DIR=${OUTPUT_BASE_DIR:-${SCRIPT_DIR}/output}

declare -a INPUT_LOG_RATES=("1000" "5000" "10000" "50000" "100000")
declare -a TEST_SCENARIOS=("tail_tcp" "tail_https" "tail_null")

export INPUT_LOG_SIZE=${INPUT_LOG_SIZE:-1000}
export IMAGE_NAME=${IMAGE_NAME:-https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004}
export MACHINE_TYPE=${MACHINE_TYPE:-e2-highcpu-8}
export RUN_TIMEOUT_MINUTES=${RUN_TIMEOUT_MINUTES:-5}
export GCP_PROJECT=${GCP_PROJECT:-calyptia-benchmark}
export DISABLE_LOGSTASH=${DISABLE_LOGSTASH:-yes}
export DISABLE_STANZA=${DISABLE_STANZA:-yes}
export DISABLE_VECTOR=${DISABLE_VECTOR:-yes}
export DISABLE_CALYPTIA_LTS=${DISABLE_CALYPTIA_LTS:-yes}

function run_test() {
    local initial_name="${INPUT_VM_NAME_PREFIX}-${1}-${2}"
    local name=${initial_name/_/-}
    TEST_SCENARIO="${1:?}" \
    INPUT_LOG_RATE="${2:?}" \
    OUTPUT_DIR="${3:?}" \
    VM_NAME="${name}" \
        "$SCRIPT_DIR"/../../standalone/run-gcp-test.sh
}

for scenario in "${TEST_SCENARIOS[@]}"
do
    for rate in "${INPUT_LOG_RATES[@]}"
    do
        output_dir="${OUTPUT_BASE_DIR}/${scenario}_${rate}"
        mkdir -p "$output_dir"
        run_test "$scenario" "$rate" "$output_dir" &> "$output_dir"/test-run.log &
    done
    echo "Running $scenario tests"
    wait
done

echo "Complete"
