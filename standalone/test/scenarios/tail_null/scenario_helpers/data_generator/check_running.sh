#!/bin/bash
set -eu
CONTAINER_NAME=${CONTAINER_NAME:-data-generator}

# https://stackoverflow.com/a/43723174
if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" != "true" ]; then
    echo "Data generator is not running: $CONTAINER_NAME"
    docker ps
fi
