```


           ⟋ ‾‾‾‾⟋|
           ██████  |
           ██████  |
           ██████ ⟋ ‾‾‾⟋|
         ⟋     ⟋██████  |
        ██████   ██████  |
        ██████   ██████⟋
        ██████⟋

            [Charts]

```

<div align="start">
  <p>
    <a href="https://rulebricks.com">Website</a> •
    <a href="https://rulebricks.com/docs">Documentation</a> •
    <a href="#support">Support</a>
  </p>
</div>

---

Resources to deploy custom configurations of Rulebricks and its dependencies via Helm.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support (e.g., AWS EBS CSI driver)
- A domain name you control

See [Minimum Cluster Requirements](example-min-cluster.yaml) for an example EKS cluster configuration.

## Quick Start

```bash
# Install from OCI registry (follow on-screen instructions for DNS & TLS setup)
helm install rulebricks oci://ghcr.io/rulebricks/charts/stack \
  --namespace rulebricks \
  --create-namespace \
  -f values.yaml \
  --set global.licenseKey=<YOUR_LICENSE_KEY>
```

After installation, Helm will display instructions for configuring DNS and enabling TLS.

## Configuration

### Global Settings

| Parameter                    | Description                                         | Default                   |
| ---------------------------- | --------------------------------------------------- | ------------------------- |
| `global.domain`              | Base domain for the deployment                      | `rulebricks.local`        |
| `global.email`               | Admin email (required for TLS certificates)         | `admin@rulebricks.com`    |
| `global.licenseKey`          | Rulebricks Enterprise license key                   | `evaluation`              |
| `global.tlsEnabled`          | Enable TLS/HTTPS (set after DNS is configured)      | `false`                   |
| `global.migrations.enabled`  | Run database migrations automatically               | `true`                    |
| `global.smtp.host`           | SMTP server hostname                                | `smtp.mailtrap.io`        |
| `global.smtp.port`           | SMTP server port                                    | `2525`                    |
| `global.smtp.user`           | SMTP username                                       | —                         |
| `global.smtp.pass`           | SMTP password                                       | —                         |
| `global.smtp.from`           | Sender email address                                | `no-reply@rulebricks.com` |
| `global.smtp.fromName`       | Sender display name                                 | `Rulebricks`              |
| `global.supabase.url`        | External Supabase URL (leave empty for self-hosted) | `""`                      |
| `global.supabase.anonKey`    | Supabase anonymous/public key                       | _(demo key)_              |
| `global.supabase.serviceKey` | Supabase service role key                           | _(demo key)_              |
| `global.supabase.jwtSecret`  | JWT signing secret (self-hosted only)               | _(demo secret)_           |
| `global.ai.enabled`          | Enable AI-powered rule generation                   | `false`                   |
| `global.ai.openaiApiKey`     | OpenAI API key for AI features                      | `""`                      |

### Storage Class (AWS)

The chart automatically creates a `gp3` StorageClass for AWS EBS. Disable with `storageClass.create: false` if you have your own.

---

<details>
<summary><strong>Using Managed Supabase (Cloud)</strong></summary>

If you prefer Supabase Cloud instead of self-hosting:

1. **Extract migration files** from the app image:

   ```bash
   docker create --name temp-rb rulebricks/app:latest
   docker cp temp-rb:/opt/rulebricks/assets/supabase ./supabase
   docker rm temp-rb
   ```

2. **Push schema to your Supabase project**:

   ```bash
   cd supabase
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase db push --include-all
   ```

3. **Configure Helm values**:

   ```yaml
   supabase:
     enabled: false

   global:
     migrations:
       enabled: false # Already ran manually
     supabase:
       url: "https://<project-ref>.supabase.co"
       anonKey: "<your-anon-key>"
       serviceKey: "<your-service-role-key>"
   ```

</details>

<details>
<summary><strong>Using External Kafka</strong></summary>

To connect to an existing Kafka cluster:

```yaml
kafka:
  enabled: false

rulebricks:
  app:
    logging:
      kafkaBrokers: "kafka-1:9092,kafka-2:9092"
```

</details>

<details>
<summary><strong>S3 Log Storage (AWS)</strong></summary>

To send rule execution logs to S3:

1. **Create an IAM policy** (`vector-s3-policy.json`):

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

2. **Set up IRSA** (IAM Roles for Service Accounts):

   ```bash
   # Create OIDC provider (if needed)
   eksctl utils associate-iam-oidc-provider --cluster=YOUR_CLUSTER --approve

   # Create IAM policy
   aws iam create-policy --policy-name VectorS3Access --policy-document file://vector-s3-policy.json

   # Create service account
   eksctl create iamserviceaccount \
     --cluster=YOUR_CLUSTER \
     --namespace=rulebricks \
     --name=vector-s3-access \
     --attach-policy-arn=arn:aws:iam::YOUR_ACCOUNT:policy/VectorS3Access \
     --approve
   ```

3. **Configure Vector** in `values.yaml`:

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

> For GCS or Azure Blob, see the [Vector sinks documentation](https://vector.dev/docs/reference/configuration/sinks/).

</details>

---

## Architecture

| Component                 | Description                                        | Enabled |
| ------------------------- | -------------------------------------------------- | :-----: |
| **rulebricks**            | Core application and high-performance solver (HPS) |    ✓    |
| **supabase**              | Backend services (Postgres, Auth, REST API)        |    ✓    |
| **kafka**                 | Message queuing for async rule execution           |    ✓    |
| **traefik**               | Ingress controller with automatic TLS              |    ✓    |
| **cert-manager**          | Let's Encrypt certificate provisioning             |    ✓    |
| **keda**                  | Event-driven autoscaling for HPS workers           |    ✓    |
| **vector**                | Log aggregation and forwarding                     |    ✓    |
| **kube-prometheus-stack** | Metrics collection (Prometheus)                    |    ✗    |

---

<details>
<summary><strong>Troubleshooting</strong></summary>

### TLS Certificate Issues

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate status
kubectl get certificates -n rulebricks
kubectl describe certificate rulebricks-tls -n rulebricks

# Check ClusterIssuer
kubectl describe clusterissuer rulebricks-letsencrypt
```

### Database Migration Issues

```bash
kubectl logs job/rulebricks-db-migrate-1 -n rulebricks
```

### Pod Issues

```bash
kubectl get pods -n rulebricks
kubectl describe pod <pod-name> -n rulebricks
kubectl logs <pod-name> -n rulebricks
```

</details>
