![Rulebricks Cloud Banner](https://d1zic6dm9txw4h.cloudfront.net/rulebricks-docs-assets/static/images/private-deployment/rb-cloud-banner.png)

<div align="start">
  <p>
    <a href="https://rulebricks.com">Website</a> •
    <a href="https://rulebricks.com/docs/private-deployment/quick-start">Full Documentation</a> •
    <a href="mailto:support@rulebricks.com">Support</a>
  </p>
</div>

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
| `global.tlsEnabled`                  | Enable TLS/HTTPS (set after DNS is configured or with external-dns)       |
| `global.externalDnsEnabled`          | Add external-dns annotations to ingresses for automatic DNS management    |
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
| `global.supabase.projectRef`         | Project reference (Cloud Supabase)                                        |
| `global.supabase.accessToken`        | Access token for Supabase CLI (Cloud Supabase)                            |
| `global.supabase.jwtSecret`          | JWT signing secret (self-hosted only)                                     |
| `global.ai.enabled`                  | Enable AI-powered rule generation                                         |
| `global.ai.openaiApiKey`             | OpenAI API key for AI features                                            |
| `global.sso.enabled`                 | Enable Enterprise SSO                                                     |
| `global.sso.provider`                | SSO provider: `azure`, `google`, `okta`, `keycloak`, `ory`, `other`       |
| `global.sso.url`                     | Identity provider URL (required except for Google)                        |
| `global.sso.clientId`                | OAuth client ID from your IdP                                             |
| `global.sso.clientSecret`            | OAuth client secret from your IdP                                         |
| `global.secrets.secretRef`           | Reference to existing K8s secret (optional)                               |

---

### Configuration Choices

<details>
<summary><strong>Single Sign-On via OIDC</strong></summary>

Enable Single Sign-On via OIDC with your identity provider:

```yaml
global:
  sso:
    enabled: true
    provider: "ory" # azure, google, okta, keycloak, ory, other
    url: "https://your-org.projects.oryapis.com"
    clientId: "<client-id>"
    clientSecret: "<client-secret>"
```

**Native providers** (`azure`, `google`, `okta`, `keycloak`) work directly with Supabase. If using Supabase Cloud, configure the appropriate provider in the Supabase Dashboard.

**Custom providers** (`ory`, `other`) use the app's built-in OIDC proxy to translate paths. If using Supabase Cloud, configure _Keycloak_ in the Supabase Dashboard with:

- **Realm URL**: `https://<your-domain>/api/sso-proxy`
- **Client ID/Secret**: Same as your `values.yaml`

</details>

<details>
<summary><strong>Automatic DNS with External-DNS</strong></summary>

For single-phase installation without manual DNS configuration, you can use external-dns to automatically create DNS records.

#### Option 1: Deploy external-dns with this chart

```bash
helm install rulebricks oci://ghcr.io/rulebricks/charts/stack \
  --namespace rulebricks \
  --create-namespace \
  -f your-values.yaml \
  --set external-dns.enabled=true \
  --set global.externalDnsEnabled=true \
  --set global.tlsEnabled=true
```

Configure provider-specific settings in your values file:

```yaml
external-dns:
  enabled: true
  provider: route53 # or: cloudflare, google, azure

global:
  externalDnsEnabled: true
  tlsEnabled: true
```

#### Option 2: Use existing cluster-wide external-dns

If external-dns is already installed in your cluster:

```bash
helm install rulebricks oci://ghcr.io/rulebricks/charts/stack \
  --namespace rulebricks \
  --create-namespace \
  -f your-values.yaml \
  --set global.externalDnsEnabled=true \
  --set global.tlsEnabled=true
```

This adds the necessary annotations to ingresses for your existing external-dns to discover.

#### DNS Records Created

When `global.externalDnsEnabled=true`, the following records are configured:

- `<global.domain>` → Traefik LoadBalancer
- `supabase.<global.domain>` → Traefik LoadBalancer (if self-hosting Supabase)

</details>

<details>
<summary><strong>Using Supabase Cloud</strong></summary>

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
| **external-dns**          | Automatic DNS record management                    |    ✗    |
| **kube-prometheus-stack** | Metrics collection (Prometheus)                    |    ✗    |

---

<details>
<summary><strong>Deployment Troubleshooting</strong></summary>

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

### Supabase Setup/Migration Issues

These are usually caused by inaccurate values, or the Supabase Cloud project not being created yet.

```bash
kubectl logs job/rulebricks-managed-supabase-setup-1 -n rulebricks
```

```bash
kubectl logs job/rulebricks-db-migrate-1 -n rulebricks
```

</details>

---

## Benchmarking

Check out our [benchmarking toolkit](./benchmarks/README.md) to test application performance under load. It gives you a simple, but out-of-the-box way to evaluate the performance of your Rulebricks deployment and make informed decisions around configuration values.
