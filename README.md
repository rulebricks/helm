# Rulebricks Enterprise Helm Chart

This chart deploys Rulebricks and its dependencies (Supabase, Kafka, etc.) to a Kubernetes cluster. It is designed to be a self-contained "umbrella" chart that can be used to spin up a full stack, or configured to connect to existing external infrastructure.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support in the underlying infrastructure
- A domain name pointing to your cluster's ingress (for TLS)

## Installation

1.  **Add the Rulebricks Enterprise Helm Repository**:

    ```bash
    helm repo add rulebricks-enterprise https://github.com/rulebricks/helm/releases/latest/download
    helm repo update
    ```

2.  **Configure `values.yaml`**:
    Download the default [values.yaml](https://github.com/rulebricks/helm/blob/main/values.yaml) and edit it to set your domain, license key, and secrets.

    **CRITICAL**: You must change the default passwords and keys in `supabase.secret` before deploying to production.

3.  **Install**:
    ```bash
    helm install rulebricks rulebricks-enterprise/rulebricks-enterprise \
      --namespace rulebricks \
      --create-namespace \
      -f values.yaml
    ```

## TLS Certificate Management

**TLS is mandatory for Rulebricks.** This chart integrates with **cert-manager** for automatic TLS certificate provisioning via Let's Encrypt.

### Setup Guide

1.  **Configure Global Settings**:
    Set your email address (required for Let's Encrypt) and your domain in `values.yaml`:

    ```yaml
    global:
      domain: "rulebricks.example.com"
      email: "admin@example.com"
    ```

2.  **DNS Configuration**:
    Ensure your domain points to the LoadBalancer IP of the Traefik service.
    - If installing on a new cluster, run the install first, get the LoadBalancer IP (`kubectl get svc -n rulebricks`), update your DNS A record, and then wait for propagation.
    - **cert-manager** will automatically attempt to provision a certificate once the DNS resolves.

### Using Existing Cert Manager

If you already have `cert-manager` installed in your cluster:

1.  Disable the bundled installation:

    ```yaml
    cert-manager:
      enabled: false
    ```

2.  Ensure your existing `cert-manager` can satisfy the `Certificate` resources created by this chart, or configure the chart to use your existing `ClusterIssuer` if applicable (refer to chart templates for issuer details).

### Using Existing Traefik / Ingress

Rulebricks relies heavily on Traefik's middleware and routing capabilities. If you have an existing ingress controller (even Traefik), it is **strongly recommended** to let Rulebricks deploy its own dedicated Traefik instance to avoid configuration conflicts.

If you must use an existing ingress:

1.  Disable Traefik: `traefik.enabled: false`.
2.  You will need to manually create Ingress resources that match the routing logic provided by the chart. This is an advanced configuration and not fully supported out-of-the-box.

## Automated Database Migrations

This chart includes a Helm hook that automatically runs database migrations on install and upgrade.

- A Kubernetes Job runs `post-install` and `post-upgrade`.
- It applies migration scripts from the app image to the Postgres database.

You can disable this automation by setting `migrations.enabled: false` in `values.yaml`.

> **Note**: If you are using an external or managed Supabase instance, you **must** disable this job and run migrations manually (see below).

## Configuration

### Global Settings

| Parameter       | Description                                 | Default                |
| --------------- | ------------------------------------------- | ---------------------- |
| `global.domain` | The base domain for the deployment          | `rulebricks.local`     |
| `global.email`  | Admin email (required for TLS certificates) | `admin@rulebricks.com` |

## Using External Services

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

1.  Check cert-manager logs:

    ```bash
    kubectl logs -n cert-manager -l app=cert-manager
    ```

2.  Check certificate status:

    ```bash
    kubectl get certificates -n <namespace>
    kubectl describe certificate <release-name>-tls -n <namespace>
    ```

3.  Check ClusterIssuer status:
    ```bash
    kubectl describe clusterissuer <release-name>-letsencrypt
    ```

### Database Migration Issues

Check the migration job logs:

```bash
kubectl logs job/<release-name>-db-migrate-<revision> -n <namespace>
```
