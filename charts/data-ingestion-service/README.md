# Data Ingestion Service Helm Chart

This Helm chart deploys the Akto Data Ingestion Service on a Kubernetes cluster.

## Installation

```bash
helm install data-ingestion-service ./charts/data-ingestion-service
```

## Configuration

The following table lists the configurable parameters and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `dataIngestionService.image.tag` | Image tag | `latest` |
| `dataIngestionService.replicas` | Number of replicas | `1` |
| `dataIngestionService.env.aktoTrafficBatchSize` | Traffic batch size | `100` |
| `dataIngestionService.env.aktoTrafficBatchTimeSecs` | Traffic batch time in seconds | `10` |
| `dataIngestionService.env.aktoKafkaBrokerUrl` | Kafka broker URL | `<mini-runtime-service-url>:9092` |
| `dataIngestionService.env.aktoKafkaProducerBatchSize` | Kafka producer batch size | `10` |
| `dataIngestionService.env.aktoKafkaProducerLingerMs` | Kafka producer linger time in ms | `10` |
| `dataIngestionService.env.aktoKafkaTopicName` | Kafka topic name | `akto.api.logs` |
| `dataIngestionService.service.type` | Service type | `ClusterIP` |
| `dataIngestionService.service.port` | Service port | `8080` |

## Example

```bash
helm install data-ingestion-service ./charts/data-ingestion-service \
  --set dataIngestionService.env.aktoKafkaBrokerUrl=<mini-runtime-service-url>:9092 \
```
