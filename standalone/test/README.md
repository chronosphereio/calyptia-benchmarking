# Simple test framework

The goal is to provide a simple automated mechanism to run a particular test scenario (or use case) for a period of time and then export any relevant information.

Each test scenario provides a directory named for it.
This directory contains the configuration for each of the tools we want to test.
It also provides any data generators or other supporting tooling required.

The structure looks like this:

- test scenario name directory
  - tool config directory
    - config files...
  - scenario_helpers/X - optional, will not be used if not present
    - check_running.sh - confirm the data generator is running on each iteration
    - run.sh - start the data generator
    - stop.sh - stop the data generator

To execute the tools we prefer to use the systemd service for that.
The intention is you configure the tools then we just run them in the standard way.
For any tools without configuration, the assumption is they are disabled for this test run.

The [`run-test.sh` script](./run-test.sh) will handle all the configuration and running of the tools followed by metric export.

## Configuration

To configure the test framework the following variables can be used.

```bash
# Set to 0 for continuous running
RUN_TIMEOUT_MINUTES=${RUN_TIMEOUT_MINUTES:-10}
# Location for any generated output
OUTPUT_DIR=${OUTPUT_DIR:-$PWD/output}
# Where all the tests are stored
TEST_ROOT=${TEST_ROOT:-$SCRIPT_DIR}
# One of the configuration scenarios to run
TEST_SCENARIO=${TEST_SCENARIO:-tail_null}
TEST_SCENARIO_DIR=${TEST_SCENARIO_DIR:-$TEST_ROOT/scenarios/$TEST_SCENARIO}
# Data will be generated and/or consumed from here
TEST_SCENARIO_DATA_DIR=${TEST_SCENARIO_DATA_DIR:-/test/data}

# Disable components by setting true/yes
DISABLE_LOGSTASH=${DISABLE_LOGSTASH:-no}
DISABLE_STANZA=${DISABLE_STANZA:-no}
DISABLE_VECTOR=${DISABLE_VECTOR:-no}
DISABLE_CALYPTIA_LTS=${DISABLE_CALYPTIA_LTS:-no}
```

As you can see, nothing should be required to run a default scenario.
Typically though the main things you would configure are:

- the scenario to run : `TEST_SCENARIO`
- the output directory for results, etc.: `OUTPUT_DIR`
- the length of time to run for: `RUN_TIMEOUT_MINUTES`
