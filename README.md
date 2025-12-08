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
  -f your-values.yaml
```

After installation, Helm will display instructions for configuring DNS and enabling TLS.

## Configuration

### Global Settings

| Parameter                            | Description                                                               |
| ------------------------------------ | ------------------------------------------------------------------------- |
| `global.domain`                      | Base domain for the deployment                                            |
| `global.email`                       | Admin email (required for TLS certificates)                               |
| `global.licenseKey`                  | Rulebricks Enterprise license key                                         |
| `global.tlsEnabled`                  | Enable TLS/HTTPS (set after DNS is configured)                            |
| `global.smtp.host`                   | SMTP server hostname                                                      |
| `global.smtp.port`                   | SMTP server port                                                          |
| `global.smtp.user`                   | SMTP username                                                             |
| `global.smtp.pass`                   | SMTP password                                                             |
| `global.smtp.from`                   | Sender email address                                                      |
| `global.smtp.fromName`               | Sender display name                                                       |
| `global.supabase.anonKey`            | Supabase anonymous/public key                                             |
| `global.supabase.serviceKey`         | Supabase service role key                                                 |
| `global.supabase.emails.subjects.*`  | Email subject customization (invite, confirmation, recovery, emailChange) |
| `global.supabase.emails.templates.*` | Email template URLs (invite, confirmation, recovery, emailChange)         |
| `global.supabase.url`                | External Supabase URL (leave empty for self-hosted)                       |
| `global.supabase.projectRef`         | Project reference for managed Supabase (optional)                         |
| `global.supabase.accessToken`        | Access token for Supabase CLI (managed only)                              |
| `global.supabase.jwtSecret`          | JWT signing secret (self-hosted only)                                     |
| `global.ai.enabled`                  | Enable AI-powered rule generation                                         |
| `global.ai.openaiApiKey`             | OpenAI API key for AI features                                            |
| `global.secrets.secretRef`           | Reference to existing K8s secret (optional)                               |

### Secrets Management

Sensitive values are stored in Kubernetes Secrets, not ConfigMaps. You have two options:

#### Option 1: Inline Values (Default)

`global.secrets.secretRef == ""`

Provide sensitive values directly in `values.yaml` or via `--set`.

```bash
# Using --set with environment variables (recommended for CI/CD)
helm install rulebricks ./helm \
  --namespace rulebricks \
  --create-namespace \
  -f values.yaml \
  --set global.licenseKey=$LICENSE_KEY \
  --set global.smtp.user=$SMTP_USER \
  --set global.smtp.pass=$SMTP_PASS \
  --set global.supabase.serviceKey=$SUPABASE_SERVICE_KEY \
  --set global.ai.openaiApiKey=$OPENAI_API_KEY
```

#### Option 2: External Secret (Enterprise)

`global.secrets.secretRef != ""`

For enterprise deployments using external secret management (Vault, AWS Secrets Manager, etc.), create a Kubernetes secret first and reference it. This is all-or-nothing– you cannot mix and match inline values and external secrets.

> **Note:** Self-hosted Supabase internal secrets (JWT, DB password, dashboard) are configured via `values.yaml` and stored in separate Kubernetes secrets managed by the Supabase subchart.

```bash
# Create the secret manually or via your secret management tool
kubectl create secret generic rulebricks-secrets \
  --namespace rulebricks \
  --from-literal=LICENSE_KEY="your-license-key" \
  --from-literal=SMTP_USER="smtp-username" \
  --from-literal=SMTP_PASS="smtp-password" \
  --from-literal=SUPABASE_ANON_KEY="your-anon-key" \
  --from-literal=SUPABASE_SERVICE_KEY="your-service-key" \
  --from-literal=SUPABASE_ACCESS_TOKEN="your-access-token" \
  --from-literal=OPENAI_API_KEY="your-openai-key"

# Reference it in Helm
helm install rulebricks ./helm \
  --namespace rulebricks \
  -f values.yaml \
  --set global.secrets.secretRef=rulebricks-secrets
```

You can customize the key names in the external secret via `global.secrets.secretRefKeys`:

```yaml
global:
  secrets:
    secretRef: "my-external-secret"
    secretRefKeys:
      licenseKey: "MY_LICENSE_KEY" # default: LICENSE_KEY
      smtpUser: "MY_SMTP_USER" # default: SMTP_USER
      smtpPass: "MY_SMTP_PASS" # default: SMTP_PASS
      supabaseAnonKey: "MY_ANON_KEY" # default: SUPABASE_ANON_KEY
      supabaseServiceKey: "MY_SVC_KEY" # default: SUPABASE_SERVICE_KEY
      supabaseAccessToken: "MY_TOKEN" # default: SUPABASE_ACCESS_TOKEN
      openaiApiKey: "MY_OPENAI_KEY" # default: OPENAI_API_KEY
```

---

<details>
<summary><strong>Using Supabase Cloud - Automatic Setup</strong></summary>

Even if you use Supabase Cloud instead of self-hosting, this chart will automatically configure your project. You will need to find and provide certain information from your newly created account/project as values.

1. **Create a Supabase project** at [supabase.com](https://supabase.com) if you haven't already.

2. **Generate an access token** from Supabase Dashboard: Account Settings > Access Tokens.

3. **Get your project details** from the Supabase Dashboard:

   - Project URL (e.g., `https://abcdefghijkl.supabase.co`)
   - Anon (public) key
   - Service role key

4. **Configure Helm values**:

   ```yaml
   supabase:
     enabled: false

   global:
     supabase:
       url: "https://<project-ref>.supabase.co"
       anonKey: "<your-anon-key>"
       serviceKey: "<your-service-role-key>"
       accessToken: "<your-supabase-access-token>"
       # Optional: explicitly set project ref (derived from URL if empty)
       projectRef: ""
   ```

The migration job will:

- Authenticate with your Supabase account using the access token
- Link to your project
- Push the database schema via `supabase db push`
- Configure auth settings based on your domain

</details>

<details>
<summary><strong>Forwarding Decision Logs</strong></summary>

This is one example of forwarding rule execution (decision) logs to S3. Under the hood, we use Vector, which can be configured to forward logs to a wide variety of otherdestinations.

See the [Vector documentation](https://vector.dev/docs/reference/configuration/sinks/) for more information.

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

There are two major components here– our core stack, and Supabase, our db/auth provider.

You can choose to self-host Supabase, or create a project in Supabase Cloud– either way, this
chart will try to automate all configuration and migration work for you.

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

### Retry Installation

```bash
helm uninstall rulebricks -n rulebricks
# Clear PVCs
kubectl delete pvc --all -n rulebricks
helm install rulebricks oci://ghcr.io/rulebricks/charts/stack -n rulebricks -f your-values.yaml
```

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

### Database Migration Issues (Self-Hosted)

```bash
kubectl logs job/rulebricks-db-migrate-1 -n rulebricks
```

### Managed Supabase Setup Issues

```bash
kubectl logs job/rulebricks-managed-supabase-setup-1 -n rulebricks
```

### Pod Issues

```bash
kubectl get pods -n rulebricks
kubectl describe pod <pod-name> -n rulebricks
kubectl logs <pod-name> -n rulebricks
```

</details>
