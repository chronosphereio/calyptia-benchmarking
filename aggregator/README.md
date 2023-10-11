# Aggregator benchmarking

We provide a simple script to run up multiple input VMs sending via TCP to a single Calyptia Core aggregator VM.

![Aggregator benchmarking overview](../resources/diagrams/Aggregator%20benchmarking.png)

This is all configurable via the environment variables below:

| Name | Description | Default |
|------|-------------|---------|
|INPUT_VM_NAME_PREFIX| Prefix for each input VM followed by the index. | benchmark-instance-input |
|INPUT_IMAGE_NAME| The image to use for each of the input VMs | <https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004> |
|INPUT_MACHINE_TYPE| The GCP machine type for each of the input VMs | e2-highcpu-8 |
|INPUT_VM_COUNT| The number of input VMs to run. | 3 |
|INPUT_LOG_RATE| The number of log messages to generate per second on each input VM. | 20000 |
|INPUT_LOG_SIZE| The size of each log message in bytes. | 1000 |
||||
|CORE_VM_NAME| The name of the aggregator VM instance to create | benchmark-instance-core |
|CORE_IMAGE_NAME| The image to use for the aggregator VM. | <https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-core-benchmark-ubuntu-2004> |
|CORE_MACHINE_TYPE| The GCP machine type for each of the input VMs | e2-highcpu-16 |
|CORE_PORT| The port to use for forwarding traffic from the input VMs to the Core VM | 5000 |
||||
|TEST_SCENARIO| The test scenario we want to run. | tcp_input |
|ENABLE_CORE| Enable Calyptia Core aggregator, mutually exclusive with other `ENABLE_` options and remember to disable if using others. | yes |
|ENABLE_FLUENTD| Enable Fluentd aggregator, mutually exclusive with other `ENABLE_` options. | no |

We require you to provide the following environment variables:

- CALYPTIA_CLOUD_PROJECT_TOKEN: The Calyptia Cloud project token to use.
- CALYPTIA_CLOUD_AGGREGATOR_NAME: The Calyptia Cloud aggregator name to use, this should be unique and not existing prior to running the script (remove any old ones if reusing)

Testing of individual aggregator solutions is mutually exclusive with this test script: a single aggregator VM is created with only one of the tools enabled.
Repeat the test with a different tool as required using the `ENABLE_` options above.

## Public dashboards

We have a project set up in Grafana Cloud to receive the various metrics.

Follow the guidance here to set up Fluent Bit to forward local node metrics (node_exporter equivalent) to Grafana Cloud: <https://calyptia.com/2022/03/23/how-to-send-openshift-logs-and-metrics-to-datadog-elastic-and-grafana/>
The reason for using Fluent Bit is that it simplifies that set up by having a single agent collect and forward the information.
Otherwise you can use node_exporter with a local Prometheus proxy or similar to remote write the collected data: <https://grafana.com/docs/grafana-cloud/data-configuration/metrics/metrics-prometheus/>

For Grafana Cloud usage we need various API keys and configuration set up and this is not part of the VM for obvious reasons on security.

The `/etc/fluent-bit/custom.conf` file can be used to provide these as enviroment variables to the Fluent Bit systemd service.
The test script provides support for a `.env` file in this directory to provide them:

```bash
$ cat .env
GRAFANA_CLOUD_PROM_URL=https://prometheus-prod-10-prod-us-central-0.grafana.net
GRAFANA_CLOUD_PROM_USERNAME=123456
GRAFANA_CLOUD_APIKEY='XXXX'
```

Similarly a cloud-init approach can be used to set this up as part of VM creation.

## Running a test

### Required settings

- Config a default project with appropriate permissions

```shell
gcloud config set project calyptia-benchmark
```

- Config a default zone

```shell
gcloud config set compute/zone us-central1-a
```

- Set the Calyptia Cloud project token

```shell
export CALYPTIA_CLOUD_PROJECT_TOKEN=XXXX
```

### Recommended settings

```shell
export INPUT_VM_NAME_PREFIX=benchmark-instance-input-fwd
export CORE_VM_NAME=benchmark-instance-core-fwd
export TEST_SCENARIO=forward_input
export CALYPTIA_CLOUD_AGGREGATOR_NAME=benchmark-forward
```

### Run the test

```shell
./run-gcp-test.sh
```

## Known issues

- Script is stuck in `Waiting for SSH access to`
> Ensure that the default project and the default zone are set correctly.
