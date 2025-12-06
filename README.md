# Rulebricks Standalone Helm Chart

This chart deploys Rulebricks and its dependencies (Supabase, Kafka, etc.) to a Kubernetes cluster. It is designed to be a self-contained "umbrella" chart that can be used to spin up a full stack, or configured to connect to existing external infrastructure.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support in the underlying infrastructure
- A domain name pointing to your cluster's ingress (for TLS)

## Installation

1.  **Clone the repository** (if not already done).

2.  **Update Dependencies**:
    Dependencies are managed locally in the `charts/` directory and via remote repositories.

    ```bash
    helm dependency update standalone-chart/
    ```

3.  **Configure `values.yaml`**:
    Edit `standalone-chart/values.yaml` to set your domain, license key, and secrets.

    **CRITICAL**: You must change the default passwords and keys in `supabase.secret` before deploying to production.

4.  **Install**:
    ```bash
    helm install rulebricks standalone-chart/ --namespace rulebricks --create-namespace
    ```

## TLS Certificate Management

This chart integrates with **cert-manager** for automatic TLS certificate provisioning via Let's Encrypt.

### How It Works

1. When `cert-manager.enabled: true` and `rulebricks.app.tlsEnabled: true`:

   - A `ClusterIssuer` is created for Let's Encrypt
   - A `Certificate` resource is created for your domain(s)
   - The certificate is stored in a Kubernetes Secret
   - Traefik automatically uses this certificate for HTTPS

2. **Required Configuration**:

   ```yaml
   global:
     email: "your-email@example.com" # Required for Let's Encrypt registration

   rulebricks:
     app:
       tlsEnabled: true
     ingress:
       hosts:
         - host: "your-domain.com"
           paths:
             - path: /
               pathType: Prefix

   cert-manager:
     enabled: true
     installCRDs: true
   ```

3. **DNS Requirements**:
   - Your domain must point to the Traefik LoadBalancer IP
   - HTTP-01 challenge requires port 80 to be accessible from the internet

### Disabling TLS

For local development or environments with external TLS termination:

```yaml
rulebricks:
  app:
    tlsEnabled: false

cert-manager:
  enabled: false
```

## Automated Database Migrations

This chart includes a Helm hook that automatically runs database migrations on install and upgrade.

- The application image contains migration scripts in `/opt/rulebricks/assets/supabase`.
- A Kubernetes Job runs `post-install` and `post-upgrade`.
- This Job extracts the scripts from the app image and applies them to the Postgres database, tracking applied migrations in a `schema_migrations` table.

You can disable this automation by setting `migrations.enabled: false` in `values.yaml`.

> **Note**: If you are using an external or managed Supabase instance, you must disable this job and run migrations manually (see Managed Supabase Setup), as the job is configured to connect to the self-hosted instance.

## Configuration

### Global Settings

| Parameter       | Description                                 | Default                |
| --------------- | ------------------------------------------- | ---------------------- |
| `global.domain` | The base domain for the deployment          | `rulebricks.local`     |
| `global.email`  | Admin email (required for TLS certificates) | `admin@rulebricks.com` |

### Dependencies

You can enable or disable specific components if you have existing infrastructure:

| Component                 | Enable Flag            | Description                                                             |
| ------------------------- | ---------------------- | ----------------------------------------------------------------------- |
| **Supabase**              | `supabase.enabled`     | Embedded Postgres/Supabase stack. Disable to use external DB.           |
| **Kafka**                 | `kafka.enabled`        | Embedded Kafka broker. Disable to use external Kafka.                   |
| **Vector**                | `vector.enabled`       | Stateless log aggregator that consumes from Kafka (enabled by default). |
| **Traefik**               | `traefik.enabled`      | Ingress controller. Disable if you have an existing Ingress.            |
| **KEDA**                  | `keda.enabled`         | Event-driven autoscaling.                                               |
| **Cert-Manager**          | `cert-manager.enabled` | TLS certificate management via Let's Encrypt.                           |
| **kube-prometheus-stack** | `monitoring.enabled`   | Prometheus (Grafana disabled) with optional remote-write configuration. |

### Service Naming

All services use templated names based on the Helm release name. This allows multiple installations in the same namespace and ensures consistency.

**Service Name Format:**

- App: `<release-name>-app`
- HPS: `<release-name>-hps`
- HPS Worker: `<release-name>-hps-worker`
- Redis: `<release-name>-redis`
- Serverless Redis HTTP: `<release-name>-serverless-redis-http`

**External Service References (auto-discovered):**

- Kafka: `<release-name>-kafka.<namespace>.svc.cluster.local:9092`
- Supabase Kong: `http://<release-name>-supabase-kong.<namespace>.svc.cluster.local:8000`
- Supabase DB: `<release-name>-supabase-db`

### Default Secrets & Credentials

The CLI generates a large set of secrets at deploy time. To keep the Helm install experience friction-free, this chart ships **demo-only** credentials in `values.yaml`. They are good enough to bring the stack up locally but **MUST** be rotated before production. Replace every `change-me` or `demo` string with values from your secret manager.

### Logging (Vector)

Vector is deployed automatically as a stateless aggregator that consumes the `logs` topic from Kafka. By default it writes to stdout, but you can configure enterprise sinks (S3, Datadog, Splunk, etc.) under the `vector.customConfig.sinks` section.

**Note**: If using a custom release name, update the `bootstrap_servers` in the Vector config to match: `<release-name>-kafka:9092`

### Monitoring (Prometheus Remote Write)

Grafana has been removed. Instead we install Prometheus only (`kube-prometheus-stack`) and disable the bundled Grafana/Alertmanager. Prometheus retains 7 days of data locally and exposes a `remoteWrite` array under `kube-prometheus-stack.prometheus.prometheusSpec.remoteWrite`. Populate that list to forward metrics into your existing observability platform.

## Using External Services

### External Database

To use an external Postgres database (instead of embedded Supabase):

1.  Set `supabase.enabled: false`.
2.  Configure `rulebricks.app.supabaseUrl` to point to your Supabase instance or compatible API.
3.  Set the appropriate `rulebricks.app.supabaseAnonKey` and `rulebricks.app.supabaseServiceKey`.

### Managed Supabase Setup

If you prefer to use Supabase Cloud (Managed) instead of self-hosting, follow this one-time setup process:

1.  **Prerequisites**: Install the [Supabase CLI](https://supabase.com/docs/guides/cli) and [Docker](https://docs.docker.com/get-docker/).

2.  **Extract Supabase Assets**:
    The necessary configuration and migration files are packaged in the application image. Run the following to extract them to a local `supabase` directory:

    ```bash
    # Create a temporary container
    docker create --name temp-rb rulebricks/app:latest

    # Extract the assets
    docker cp temp-rb:/opt/rulebricks/assets/supabase ./supabase

    # Clean up
    docker rm temp-rb
    ```

3.  **Initialize Supabase Project**:

    - **Login and Create Project**:

      ```bash
      supabase login
      supabase projects create rulebricks --org-id <your-org-id> --db-password <secure-password> --region <region>
      # Or use an existing project
      ```

    - **Link Project**:
      ```bash
      cd supabase
      supabase link --project-ref <your-project-ref>
      ```
    - **Push Database Schema**:
      ```bash
      supabase db push --include-all
      ```
    - **Configure Auth & Settings**:
      Edit `supabase/config.toml` and replace `env(FULL_URL)` with your actual application domain (e.g., `https://rulebricks.example.com`).

      Then push the configuration:

      ```bash
      supabase config push
      ```

4.  **Get Credentials**:
    Retrieve your project URL and API keys:

    ```bash
    supabase projects api-keys
    ```

5.  **Configure Helm**:
    Update your `values.yaml` to disable the self-hosted stack and use your managed instance:

    ```yaml
    # Disable self-hosted Supabase
    supabase:
      enabled: false

    # Disable in-cluster migrations (you ran them manually above)
    migrations:
      enabled: false

    rulebricks:
      app:
        # Set your Managed Supabase URL
        supabaseUrl: "https://<your-project-ref>.supabase.co"

        # Set your keys (retrieved in step 4)
        supabaseAnonKey: "<your-anon-key>"
        supabaseServiceKey: "<your-service-role-key>"
    ```

### External Kafka

To use an external Kafka cluster:

1.  Set `kafka.enabled: false`.
2.  Configure `rulebricks.app.logging.kafkaBrokers` with your Kafka bootstrap servers.
3.  Update the Vector config's `bootstrap_servers` if using Vector.

## Architecture

This chart composes several subcharts:

- **rulebricks**: The core application and high-performance solver (HPS).
- **supabase**: A fork of the Supabase community chart for backend services.
- **kafka**: Bitnami Kafka chart for message queuing.
- **traefik**: Ingress controller with TLS support.
- **cert-manager**: Automatic TLS certificate provisioning.
- **keda**: Event-driven autoscaling for HPS workers.
- **vector**: Log aggregation and forwarding.
- **kube-prometheus-stack**: Metrics collection (Prometheus only).

## Troubleshooting

### TLS Certificate Issues

1. Check cert-manager logs:

   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

2. Check certificate status:

   ```bash
   kubectl get certificates -n <namespace>
   kubectl describe certificate <release-name>-tls -n <namespace>
   ```

3. Check ClusterIssuer status:
   ```bash
   kubectl describe clusterissuer <release-name>-letsencrypt
   ```

### Service Discovery Issues

If services cannot connect to each other, verify the service names match:

```bash
# List all services
kubectl get svc -n <namespace>

# Check service endpoints
kubectl get endpoints -n <namespace>
```

### Database Migration Issues

Check the migration job logs:

```bash
kubectl logs job/<release-name>-db-migrate-<revision> -n <namespace>
```
