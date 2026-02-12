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
| `global.scheduling.nodeSelector`     | Node selector applied to all workloads                                    |
| `global.scheduling.tolerations`      | Tolerations applied to all workloads                                      |
| `global.scheduling.affinity`         | Affinity rules applied to all workloads                                   |
| `global.labels`                      | Labels applied to all resource metadata                                   |
| `global.annotations`                 | Annotations applied to all resource metadata                              |
| `global.podLabels`                   | Labels applied to pod templates only                                      |
| `global.podAnnotations`              | Annotations applied to pod templates only                                 |

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

---

### Advanced Configuration

<details>
<summary><strong>Node Scheduling (ARM64, Dedicated Nodes)</strong></summary>

For clusters with specialized node pools (ARM64/Graviton, dedicated nodes with taints), configure global scheduling defaults:

```yaml
global:
  scheduling:
    nodeSelector:
      kubernetes.io/arch: arm64
    tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "rulebricks"
        effect: "NoSchedule"
    affinity: {}
```

These settings propagate to all workloads. Override at the component level if needed:

```yaml
rulebricks:
  app:
    nodeSelector:
      kubernetes.io/arch: arm64
    tolerations: []
```

</details>

<details>
<summary><strong>Gateway API (Alternative to Ingress)</strong></summary>

Use Kubernetes Gateway API instead of traditional Ingress resources:

```yaml
rulebricks:
  ingress:
    type: "gateway-api"  # default: "ingress"
    hostname: "app.example.com"  # override default (global.domain)
    gatewayApi:
      gatewayName: "my-gateway"
      gatewayNamespace: "gateway-system"
```

This renders `HTTPRoute` resources instead of `Ingress`. Requires a Gateway API implementation (e.g., Envoy Gateway, Cilium, Istio) in your cluster.

| `ingress.type` | Resource Created | Use Case |
|----------------|------------------|----------|
| `ingress` | `Ingress` | Standard ingress controllers (nginx, Traefik) |
| `gateway-api` | `HTTPRoute` | Gateway API implementations |

Use `ingress.hostname` when your application hostname differs from `global.domain` (e.g., `rulebricks.example.com` vs `example.com`).

</details>

<details>
<summary><strong>External Redis</strong></summary>

Use an external Redis instance instead of the bundled deployment:

```yaml
rulebricks:
  redis:
    enabled: false
    external:
      host: "redis.example.com"
      port: 6379
      password: ""  # or reference a secret
```

When `rulebricks.redis.enabled` is `false`, the chart skips deploying internal Redis and uses your external instance settings.

</details>

<details>
<summary><strong>Auth URL Configuration</strong></summary>

Override computed authentication URLs when your application hostname differs from the base domain:

```yaml
supabase:
  auth:
    # Override GOTRUE_SITE_URL (default: https://<global.domain>)
    siteUrl: "https://app.example.com"
    # Override API_EXTERNAL_URL (default: https://supabase.<global.domain>)
    externalUrl: "https://auth.example.com"
    # Add URLs to GOTRUE_URI_ALLOW_LIST
    additionalRedirectUrls:
      - "https://app.example.com/callback"
      - "https://staging.example.com/*"
```

</details>

<details>
<summary><strong>Migration Job Strategy</strong></summary>

Control how database migrations are executed:

```yaml
migrations:
  strategy: "hook"  # default
```

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| `hook` | Runs as Helm post-install/post-upgrade hook | Standard deployments |
| `deployment` | Creates job as regular resource | When post-rendering is needed |
| `manual` | Renders template without hooks | Full control over execution |

</details>

<details>
<summary><strong>Extra Environment Variables</strong></summary>

Inject additional environment variables into the application:

```yaml
rulebricks:
  app:
    extraEnv:
      - name: MY_CUSTOM_VAR
        value: "my-value"
      - name: SECRET_VAR
        valueFrom:
          secretKeyRef:
            name: my-secret
            key: secret-key
    extraEnvFrom:
      - configMapRef:
          name: my-configmap
```

</details>

<details>
<summary><strong>Global Labels and Annotations</strong></summary>

Apply labels and annotations to all resources (useful for compliance, cost allocation, monitoring):

```yaml
global:
  # Applied to all resource metadata
  labels:
    team: platform
    cost-center: engineering
  annotations:
    app.kubernetes.io/part-of: rulebricks
  
  # Applied only to pod templates
  podLabels:
    sidecar.istio.io/inject: "true"
  podAnnotations:
    prometheus.io/scrape: "true"
```

</details>

<details>
<summary><strong>Per-Component Pod Labels</strong></summary>

For clusters with admission policies (Kyverno, OPA Gatekeeper) requiring specific labels on pods, configure labels at the component level:

```yaml
rulebricks:
  app:
    podLabels:
      team: platform
  redis:
    podLabels:
      team: platform
    serverlessHttp:
      podLabels:
        team: platform

supabase:
  db:
    podLabels:
      team: platform
  auth:
    podLabels:
      team: platform
  kong:
    podLabels:
      team: platform
  rest:
    podLabels:
      team: platform
  realtime:
    podLabels:
      team: platform
  meta:
    podLabels:
      team: platform
  studio:
    podLabels:
      team: platform
```

This is useful when cluster policies enforce labels like `team`, `cost-center`, or service mesh injection annotations on all pods.

</details>

<details>
<summary><strong>Resource Requests and Limits</strong></summary>

Configure CPU/memory requests and limits for each component. This is often required by cluster admission policies:

```yaml
rulebricks:
  app:
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
  redis:
    resources:
      requests:
        cpu: "50m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
    serverlessHttp:
      resources:
        requests:
          cpu: "50m"
          memory: "64Mi"
        limits:
          cpu: "200m"
          memory: "256Mi"

supabase:
  db:
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "2000m"
        memory: "2Gi"
  # Similar for: auth, kong, rest, realtime, meta, studio
```

</details>

<details>
<summary><strong>Liveness and Readiness Probes</strong></summary>

Configure health check probes for components. Required by some cluster policies:

```yaml
rulebricks:
  app:
    livenessProbe:
      httpGet:
        path: /api/health
        port: 3000
      initialDelaySeconds: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /api/health
        port: 3000
      initialDelaySeconds: 5
      periodSeconds: 5

supabase:
  auth:
    livenessProbe:
      httpGet:
        path: /health
        port: 9999
      initialDelaySeconds: 10
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /health
        port: 9999
      initialDelaySeconds: 5
      periodSeconds: 5
```

Default probes are configured for most components. Override only when needed for specific requirements.

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
