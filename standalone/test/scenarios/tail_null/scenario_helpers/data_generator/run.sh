#!/bin/bash
set -eu

INPUT_LOG_RATE=${INPUT_LOG_RATE:-20000}
INPUT_LOG_SIZE=${INPUT_LOG_SIZE:-1000}
echo "Starting data generation: $INPUT_LOG_SIZE @ $INPUT_LOG_RATE"

CONTAINER_NAME=${CONTAINER_NAME:-data-generator}

TEST_SCENARIO_DATA_DIR=${TEST_SCENARIO_DATA_DIR:-/test/data}

# We want to wipe our data for this run
rm -f "${TEST_SCENARIO_DATA_DIR:?}"/*.log
mkdir -p "${TEST_SCENARIO_DATA_DIR}"

# Remove any existing container
docker rm -f "$CONTAINER_NAME" &> /dev/null || true

docker pull --quiet fluentbitdev/fluent-bit-ci:benchmark
docker run --rm -d --name="$CONTAINER_NAME" -v "$TEST_SCENARIO_DATA_DIR":/logs/:rw \
    fluentbitdev/fluent-bit-ci:benchmark \
    /run_log_generator.py \
    --log-size-in-bytes "$INPUT_LOG_SIZE" \
    --log-rate "$INPUT_LOG_RATE" \
    --log-agent-input-type tail \
    --tail-file-path "/logs/input.log"
