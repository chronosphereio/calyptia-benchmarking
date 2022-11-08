# Calyptia Benchmarking

Supporting infrastructure and other set up for benchmarking of [Calyptia products](https://calyptia.com/products/).

We have identified two operational modes, standalone (agent forwarding) and aggregator mode (> 1 agent forward logs into a single point of aggregation).

Standalone mode:

- Calyptia Fluent Bit LTS
- OSS Fluent Bit
- Calyptia Fluentd (In progress)
- Stanza (In progress)
- Vector

Aggregator mode:

- Calyptia Core
- Calyptia Fluentd
- Vector (In progress)

For the case of the Standalone mode, we are providing the following artefacts:

- Public images in AWS and GCP that have pre-built binaries of all of the agents.
- These images have a set of configurable scenarios and parameterized run times, etc.

For the case of Aggregator mode, we are providing the following artefacts:

- A public image of Calyptia Core on AWS and GCP that has a core + AWS / Ops agent enabled to gather system level metrics to the cloud providers.
- The Calyptia Core instance will also publish the fluent-bit agent metrics into Calyptia Cloud.
- Additional tooling and scenarios to support evaluation of the other components.

These images will produce a set of Prometheus metrics that are exported and can be used to analyze the results in Grafana.
