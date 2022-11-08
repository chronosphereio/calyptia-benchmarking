#!/bin/bash
set -eu
echo "Stopping data generation"

CONTAINER_NAME=${CONTAINER_NAME:-data-generator}
docker rm -f "$CONTAINER_NAME"
