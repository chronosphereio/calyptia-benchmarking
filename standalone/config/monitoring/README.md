# Standalone monitoring stack

The intent of the standalone image is to run a single VM in isolation.
We provide this monitoring stack based on: <https://github.com/calyptia/fluent-bit-devtools/tree/main/monitoring>

The specific set up here is:

- Prometheus, Loki, Grafana locally as normal.
- Fluent Bit collecting all host metrics and logs for the PLG components.
- Process Exporter collecting process-specific metrics to allow filtering by process.
- HTTPS benchmark server: <https://github.com/calyptia/https-benchmark-server>
- TCP benchmark server: this is currently another Fluent Bit instance with a TCP input and metrics output to Prometheus.

The HTTPS and TCP servers are provided for test cases that want to use a TCP or HTTPS output.

The PLG stack will provide the following on the local VM:

- Grafana: <https://localhost:3000>
- Prometheus: <https://localhost:9090>

These ports can then be accessed or forwarded to provide full visualisation of the test scenario.
