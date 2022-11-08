#!/bin/bash
set -eu

PORT=${PORT:-514}
SENDER_RATE=${SENDER_RATE:-75000}
SIZE=${SIZE:-256}

loggen --dgram --rate="$SENDER_RATE" --size="$SIZE" --permanent 127.0.0.1 "$PORT"
