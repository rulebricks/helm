# Rulebricks Helm Charts

This chart deploys Rulebricks and its dependencies (Supabase, Kafka, etc.) to a Kubernetes cluster. It is designed to be a self-contained "umbrella" chart that can be used to spin up a full stack, or configured to connect to existing external infrastructure.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support in the underlying infrastructure
- A domain name you control (for TLS)

## Installation

We recommend a **Two-Phase Installation** to ensure DNS is correctly configured before attempting to provision TLS certificates. This prevents rate-limiting issues with Let's Encrypt.

### Phase 1: Bootstrap (HTTP only)

1.  **Add the Rulebricks Enterprise Helm Repository**:

    ```bash
    helm repo add rulebricks-enterprise https://github.com/rulebricks/helm/releases/latest/download
    helm repo update
    ```

2.  **Configure `values.yaml`**:
    Download the default [values.yaml](https://github.com/rulebricks/helm/blob/main/values.yaml) and edit `global.domain` and your secrets.

3.  **Install**:

    ```bash
    helm install rulebricks rulebricks-enterprise/rulebricks-enterprise \
      --namespace rulebricks \
      --create-namespace \
      -f values.yaml \
      --set rulebricks.app.licenseKey=<YOUR_LICENSE_KEY>
    ```

4.  **Get LoadBalancer Address**:
    After installation, wait a minute for the LoadBalancer to be provisioned, then run:

    ```bash
    kubectl get svc -n rulebricks -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
    ```

5.  **Configure DNS**:
    Create CNAME records for the following domains pointing to the address retrieved above:

    - `your-domain.com` (Main App)
    - `supabase.your-domain.com` (Backend Services)

    _Wait a few minutes for DNS to propagate._

### Phase 2: Secure (Enable TLS)

Once DNS is pointing to your cluster, enable TLS. This will automatically provision production certificates via Let's Encrypt.

1.  **Upgrade**:

    ```bash
    helm upgrade rulebricks rulebricks-enterprise/rulebricks-enterprise \
      --namespace rulebricks \
      --reuse-values \
      --set global.tlsEnabled=true \
      --set rulebricks.app.tlsEnabled=true
    ```

2.  **Verify**:
    Check that your site is now accessible via `https://`.

## Configuration

### Global Settings

| Parameter           | Description                                 | Default                |
| ------------------- | ------------------------------------------- | ---------------------- |
| `global.domain`     | The base domain for the deployment          | `rulebricks.local`     |
| `global.email`      | Admin email (required for TLS certificates) | `admin@rulebricks.com` |
| `global.tlsEnabled` | Enable TLS/SSL (Phase 2)                    | `false`                |

## Automated Database Migrations

This chart includes a Helm hook that automatically runs database migrations on install and upgrade.

- A Kubernetes Job runs `post-install` and `post-upgrade`.
- It applies migration scripts from the app image to the Postgres database.

You can disable this automation by setting `migrations.enabled: false` in `values.yaml`.

> **Note**: If you are using an external or managed Supabase instance, you **must** disable this job and run migrations manually (see below).

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

### S3 Log Storage (AWS)

To send rule execution logs to S3 instead of (or in addition to) the console, you need to:

1.  **Create an S3 bucket** for your logs.

2.  **Create an IAM policy** with permissions to write to the bucket:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": ["s3:PutObject", "s3:PutObjectAcl"],
          "Resource": "arn:aws:s3:::YOUR_BUCKET/*"
        },
        {
          "Effect": "Allow",
          "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
          "Resource": "arn:aws:s3:::YOUR_BUCKET"
        }
      ]
    }
    ```

3.  **Set up IRSA (IAM Roles for Service Accounts)** on EKS:

    ```bash
    # Create OIDC provider (if not exists)
    eksctl utils associate-iam-oidc-provider --cluster=YOUR_CLUSTER --approve

    # Create IAM policy
    aws iam create-policy \
      --policy-name VectorS3Access \
      --policy-document file://policy.json

    # Create service account with IRSA
    eksctl create iamserviceaccount \
      --cluster=YOUR_CLUSTER \
      --namespace=rulebricks \
      --name=vector-s3-access \
      --attach-policy-arn=arn:aws:iam::YOUR_ACCOUNT:policy/VectorS3Access \
      --approve
    ```

4.  **Configure Vector** in your `values.yaml`:

    ```yaml
    vector:
      serviceAccount:
        name: vector-s3-access
      customConfig:
        sinks:
          s3:
            type: aws_s3
            inputs:
              - kafka
            bucket: "your-logs-bucket"
            region: "us-east-1"
            key_prefix: "rulebricks/logs/%Y/%m/%d/"
            compression: gzip
            encoding:
              codec: json
    ```

5.  **Upgrade** your Helm release to apply the changes.

> **Note**: For GCS or Azure Blob Storage, similar patterns apply using Workload Identity (GCP) or Managed Identity (Azure). See the [Vector documentation](https://vector.dev/docs/reference/configuration/sinks/) for sink-specific configuration.

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
