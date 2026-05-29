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

See [External Services](https://rulebricks.com/docs/private-deployment/external-services) for more information on externalizing certain services.
See [Authentication](https://rulebricks.com/docs/private-deployment/sso) for more information on what happens after you configure SSO.

## Quick Start

```bash
# Install from the Rulebricks Helm OCI registry (follow on-screen instructions for DNS & TLS setup)
helm install rulebricks oci://ghcr.io/rulebricks/helm/stack \
  --namespace rulebricks \
  --create-namespace \
  -f your-values.yaml
```

After installation, Helm will display instructions for configuring DNS and enabling TLS.

### Version Pinning

Production deployments should pin both:

- a Helm chart version from the [GitHub Releases](https://github.com/rulebricks/helm/releases) page
- a Rulebricks product version through `global.version`

```bash
helm install rulebricks oci://ghcr.io/rulebricks/helm/stack \
  --namespace rulebricks \
  --create-namespace \
  --version 0.2.0 \
  -f your-values.yaml
```

```yaml
global:
  version: "1.8.17"
```

`global.version` is the single application semver. It is used for `rulebricks/app:<version>`, `rulebricks/hps:<version>`, `rulebricks/hps:worker-<version>`, and app-backed migration jobs. The chart version controls Kubernetes packaging and infrastructure templates; it does not select the Rulebricks application image version.

## Configuration

### Global Settings

| Parameter                            | Description                                                               |
| ------------------------------------ | ------------------------------------------------------------------------- |
| `global.domain`                      | Base domain for the deployment                                            |
| `global.email`                       | Admin email (required for TLS certificates)                               |
| `global.licenseKey`                  | Rulebricks Enterprise license key                                         |
| `global.version`                     | Rulebricks product version for app, HPS, HPS worker, and migration images |
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
| `global.scheduling.nodeSelector`     | Optional selector for workloads that inherit global scheduling            |
| `global.scheduling.tolerations`      | Optional tolerations for workloads that inherit global scheduling         |
| `global.scheduling.affinity`         | Optional affinity for workloads that inherit global scheduling            |
| `global.labels`                      | Labels applied to all resource metadata                                   |
| `global.annotations`                 | Annotations applied to all resource metadata                              |
| `global.podLabels`                   | Labels applied to pod templates only                                      |
| `global.podAnnotations`              | Annotations applied to pod templates only                                 |
| `global.storage.*`                   | Shared object storage used by decision logs and database backups          |
| `backup.enabled`                     | Enable self-hosted Supabase Postgres backups                              |
| `backup.schedule`                    | Cron schedule for Barman base backups                                     |
| `backup.retentionDays`               | Number of days to retain restorable backups                               |
| `backup.ttlSecondsAfterFinished`     | Seconds to retain completed backup Jobs and pod logs                      |
| `backup.jobHistory.*`                | CronJob history limits for completed backup Jobs                          |
| `migrations.ttlSecondsAfterFinished` | Seconds to retain completed migration Jobs and pod logs                   |

---

### Configuration Choices

<details>
<summary><strong>Monitoring and Remote Write</strong></summary>

Monitoring is enabled by default through `kube-prometheus-stack`. Prometheus stores metrics in-cluster unless you configure `kube-prometheus-stack.prometheus.prometheusSpec.remoteWrite`.

Rulebricks adds ServiceMonitors for the app and HPS services:

- App metrics are scraped from `/api/metrics` and cover app/admin API request counts, latency histograms, coarse rejections, and frontend error counts.
- HPS metrics are scraped from `/metrics` and cover rule-engine request counts, latency histograms, rejections, Kafka worker wait time, bulk/parallel item volume, and memory cache stats.
- Kafka JMX and ClickHouse ServiceMonitors are enabled where those charts expose Prometheus endpoints. ClickHouse metrics only apply when `clickhouse.enabled=true`. Traefik's Prometheus endpoint is enabled, but its ServiceMonitor is left as an explicit opt-in because the Traefik chart validates the Prometheus Operator CRD during template rendering.

Metric labels are intentionally bounded to avoid Prometheus cardinality problems. Labels use route templates, methods, status classes, operations, and coarse reasons. They do not include API keys, users, organizations, IP addresses, raw URLs, rule slugs, flow slugs, or error messages.

```yaml
monitoring:
  enabled: true
kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      remoteWrite:
        - url: "https://prometheus-prod-XX.grafana.net/api/prom/push"
          basicAuth:
            username:
              name: prometheus-remote-write
              key: username
            password:
              name: prometheus-remote-write
              key: password
```

Useful queries:

```promql
histogram_quantile(0.95, sum(rate(rulebricks_hps_http_request_duration_seconds_bucket[5m])) by (le, route))
sum(rate(rulebricks_hps_rejections_total[5m])) by (route, reason)
histogram_quantile(0.95, sum(rate(rulebricks_hps_kafka_request_duration_seconds_bucket[5m])) by (le, operation))
sum(rate(rulebricks_hps_bulk_items_total[5m])) by (operation)
sum(rate(rulebricks_app_frontend_errors_total[5m])) by (source)
```

After install, verify scrape discovery with:

```bash
kubectl get servicemonitor -n rulebricks
kubectl port-forward -n rulebricks svc/rulebricks-kube-prometheus-stack-prometheus 9090:9090
```

</details>

<details>
<summary><strong>Shared Object Storage and Database Backups</strong></summary>

Rulebricks uses one shared cloud provider and identity for storage-backed features, while allowing separate buckets, regions, and prefixes for high-volume decision logs and smaller database backups. If a DB backup field is left empty, it falls back to the decision-log location.

```yaml
global:
  storage:
    provider: s3 # s3, azure-blob, or gcs
    s3:
      iamRoleArn: arn:aws:iam::123456789012:role/rulebricks-storage
    decisionLogs:
      bucket: my-rulebricks-decision-logs
      region: us-west-2
      path: decision-logs
    dbBackups:
      bucket: my-rulebricks-db-backups
      region: us-west-2
      path: db-backups

backup:
  enabled: true
  schedule: "0 2 * * *"
  retentionDays: 30
  ttlSecondsAfterFinished: 2592000
  jobHistory:
    successful: 30
    failed: 30
```

Upgrade note: older values that used `global.storage.bucket`, `global.storage.region`, and `global.storage.paths.*` should move those fields under `global.storage.decisionLogs.*` and, when backups are enabled, `global.storage.dbBackups.*`.

Backups use Barman cloud tooling and are available only for self-hosted Supabase. By default, restorable backup data is retained for 30 days, and completed backup Jobs and their pod logs are retained for 30 days through both CronJob history limits and Kubernetes Job TTL. The default history limits assume the default daily schedule; increase `backup.jobHistory.successful` and `backup.jobHistory.failed` if you run backups more frequently and need every completed Job to remain visible for the full 30-day TTL window.

The backup CronJob runs with the same workload identity pattern used by Vector and ClickHouse, so bucket credentials stay in Kubernetes service account configuration instead of the database container. Migration Jobs use `migrations.ttlSecondsAfterFinished`, which also defaults to 30 days.

</details>

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
helm install rulebricks oci://ghcr.io/rulebricks/helm/stack \
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
helm install rulebricks oci://ghcr.io/rulebricks/helm/stack \
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
<summary><strong>External Kafka SSL/SASL</strong></summary>

To use external/managed Kafka, set `kafka.enabled: false` and configure `rulebricks.app.logging.kafkaBrokers` plus the optional `kafkaSsl` / `kafkaSasl` settings. The chart exposes these to the app, HPS, HPS workers, and Vector. The `wait-for-kafka` init container is automatically skipped when `kafkaBrokers` is set.

Two consumers connect to Kafka: HPS (KafkaJS, produces/consumes the solution + logs topics) and Vector (consumes the `logs` topic for the decision-log archive). They have different auth capabilities, so the right preset depends on your provider.

**AWS MSK with IAM auth** — credentials come from pod identity (IRSA), no static secrets:

```yaml
kafka:
  enabled: false
rulebricks:
  app:
    logging:
      enabled: true
      kafkaBrokers: "b-1.msk.example:9098,b-2.msk.example:9098"
      kafkaSsl: true
      kafkaSasl:
        mechanism: "aws-iam"
        region: "us-east-1"
  hps:
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/msk-access"
# Vector cannot speak MSK IAM directly, so it uses the kafka-proxy bridge sidecar:
kafkaBridge:
  enabled: true
  provider: "aws"
  region: "us-east-1"
  brokers: "b-1.msk.example:9098,b-2.msk.example:9098"
  awsRoleArn: "arn:aws:iam::ACCOUNT:role/msk-access"
vector:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/msk-access"
  extraContainers:
    - name: kafka-proxy
      image: grepplabs/kafka-proxy:latest
      args:
        - server
        - --bootstrap-server-mapping=b-1.msk.example:9098,127.0.0.1:19092
        - --bootstrap-server-mapping=b-2.msk.example:9098,127.0.0.1:19093
        - --tls-enable
        - --sasl-enable
        - --sasl-method=AWS_MSK_IAM
        - --sasl-aws-region=us-east-1
      ports:
        - containerPort: 19092
```

HPS must include the KafkaJS `oauthbearer` implementation using `aws-msk-iam-sasl-signer-js`; the chart only passes configuration to the pods.

**Azure Event Hubs (Kafka endpoint)** — SASL PLAIN with the namespace connection string. Both HPS and Vector connect directly; no bridge sidecar required:

```yaml
kafka:
  enabled: false
rulebricks:
  app:
    logging:
      enabled: true
      kafkaBrokers: "my-namespace.servicebus.windows.net:9093"
      kafkaSsl: true
      kafkaSasl:
        mechanism: "plain"
        username: "$ConnectionString"
        password: "Endpoint=sb://my-namespace.servicebus.windows.net/;SharedAccessKeyName=...;SharedAccessKey=..."
        # or: existingSecret / existingSecretUsernameKey / existingSecretPasswordKey
```

**GCP Managed Service for Apache Kafka** — OAUTHBEARER (Workload Identity) is preferred; the Vector bridge runs the GCP local auth-token server sidecar (`kafkaBridge.provider: "gcp"`, `gcpServiceAccountEmail`). A simpler `plain`/SCRAM credential also works for both consumers but uses static credentials.

Vector's Kafka source natively supports SSL + SASL `PLAIN`/`SCRAM`, but not token mechanisms (`aws-iam`, `oauthbearer`). For those, the `kafkaBridge` sidecar authenticates upstream using the Vector pod's workload identity and exposes a local plaintext listener that Vector consumes from. The CLI sets all of this automatically when you externalize Kafka; the values above are for hand-installs.

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
<summary><strong>Node Scheduling (Optional)</strong></summary>

The default chart does not require node labels, taints, architecture selectors, hard affinity, or multiple nodes. A single shared node pool is supported as long as the cluster has enough CPU, memory, and storage for the requested pods.

By default, pod templates are labeled with `rulebricks.com/workload-group`. Infrastructure includes the frontend app, Redis, Kafka, Supabase, Traefik, KEDA, cert-manager, and Vector. The compute path is HPS and HPS workers.

HPS and HPS workers use soft pod anti-affinity to prefer nodes that do not already run `rulebricks.com/workload-group=infrastructure` pods. This keeps one-node deployments valid while biasing CPU-intensive compute pods away from core services when additional nodes are available.

For normal AMD64 or ARM64 nodes, no architecture-specific Helm values are required. Multi-arch images allow Kubernetes to pull the correct image variant for the node. If your cluster taints ARM64 nodes, add the relevant tolerations explicitly:

```yaml
global:
  scheduling:
    tolerations:
      - key: kubernetes.io/arch
        operator: Equal
        value: arm64
        effect: NoSchedule

cert-manager:
  tolerations:
    - key: kubernetes.io/arch
      operator: Equal
      value: arm64
      effect: NoSchedule
  webhook:
    tolerations:
      - key: kubernetes.io/arch
        operator: Equal
        value: arm64
        effect: NoSchedule
  cainjector:
    tolerations:
      - key: kubernetes.io/arch
        operator: Equal
        value: arm64
        effect: NoSchedule

migrations:
  tolerations:
    - key: kubernetes.io/arch
      operator: Equal
      value: arm64
      effect: NoSchedule
```

Avoid `nodeSelector` or `requiredDuringSchedulingIgnoredDuringExecution` unless your platform team intentionally wants hard placement. `global.scheduling` is honored by Rulebricks workloads and migration jobs; dependency subcharts such as Kafka, Supabase, cert-manager, Traefik, KEDA, and Vector may require their own scheduling values.

</details>

<details>
<summary><strong>Kafka Image Publishing</strong></summary>

The vendored Kafka subchart defaults to `docker.io/rulebricks/kafka` so installs do not depend on the upstream image namespace at deploy time. Publish the default Kafka tag as a multi-arch manifest before releasing chart changes that reference it:

```bash
KAFKA_TAG=4.0.0-debian-12-r10 bash scripts/publish-kafka-image.sh
```

The script verifies that the source image has both `linux/amd64` and `linux/arm64` variants, then republishes the manifest list under `docker.io/rulebricks/kafka:<tag>`. The Helm chart release workflow runs the same publish step before packaging the chart.

The release workflow requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets with write access to `docker.io/rulebricks/kafka`.

</details>

<details>
<summary><strong>Gateway API (Alternative to Ingress)</strong></summary>

Use Kubernetes Gateway API instead of traditional Ingress resources:

```yaml
rulebricks:
  ingress:
    type: "gateway-api" # default: "ingress"
    hostname: "app.example.com" # override default (global.domain)
    gatewayApi:
      gatewayName: "my-gateway"
      gatewayNamespace: "gateway-system"
```

This renders `HTTPRoute` resources instead of `Ingress`. Requires a Gateway API implementation (e.g., Envoy Gateway, Cilium, Istio) in your cluster.

| `ingress.type` | Resource Created | Use Case                                      |
| -------------- | ---------------- | --------------------------------------------- |
| `ingress`      | `Ingress`        | Standard ingress controllers (nginx, Traefik) |
| `gateway-api`  | `HTTPRoute`      | Gateway API implementations                   |

Use `ingress.hostname` when your application hostname differs from `global.domain` (e.g., `rulebricks.example.com` vs `example.com`).

</details>

<details>
<summary><strong>External Auth Proxy Routing</strong></summary>

If Rulebricks is fronted by an external auth proxy such as Oathkeeper, you can suppress chart-owned app routing while keeping HPS API routes managed by the chart:

```yaml
rulebricks:
  ingress:
    enabled: true
    app:
      enabled: false
```

Use `rulebricks.ingress.enabled: false` instead when your own Ingress or HTTPRoute should own both the app catch-all route and HPS API routes.

</details>

<details>
<summary><strong>Exposing Supabase Studio</strong></summary>

Supabase Studio can be exposed on a separate hostname from the app and Kong API:

```yaml
supabase:
  studio:
    ingress:
      enabled: true
      type: "ingress" # or "gateway-api"
      hostname: "studio.example.com" # defaults to studio.<global.domain>
      annotations: {}
```

For Gateway API, set `supabase.studio.ingress.type: gateway-api` and configure `supabase.studio.ingress.gatewayApi.gatewayName`. Studio dashboard authentication is controlled by `supabase.secret.dashboard.username` and `supabase.secret.dashboard.password`.

</details>

<details>
<summary><strong>External Redis</strong></summary>

Use an external/managed Redis instance (ElastiCache, Azure Cache for Redis, Memorystore, Upstash, etc.) instead of the bundled deployment. Set `rulebricks.redis.enabled: false` and provide connection details under `rulebricks.redis.external`.

Basic TCP connection with inline password:

```yaml
rulebricks:
  redis:
    enabled: false
    external:
      host: "redis.example.com"
      port: 6379
      password: "super-secret"   # injected at runtime; never written to a ConfigMap
      tls:
        enabled: true             # uses rediss:// scheme
```

Reference an existing secret instead of an inline password (recommended for production):

```yaml
rulebricks:
  redis:
    enabled: false
    external:
      host: "redis.example.com"
      existingSecret: "my-redis-auth"
      existingSecretKey: "redis-password"
      tls:
        enabled: true
```

Upstash-style HTTP API (bypasses the in-cluster `serverless-redis-http` bridge):

```yaml
rulebricks:
  redis:
    enabled: false
    external:
      host: "redis.example.com"   # still required for the direct Redis client
      httpApi:
        enabled: true
        # inline:
        url: "https://my-db.upstash.io"
        token: "AX..."
        # or via an existing secret:
        existingSecret: "my-upstash-creds"
        existingSecretUrlKey: "redis-url"
        existingSecretTokenKey: "redis-token"
```

When `rulebricks.redis.enabled` is `false`, the chart skips the internal Redis Deployment/Service/PVC and points both the app and the `serverless-redis-http` bridge at your external instance. Passwords are injected via env at container start (using `$(REDIS_PASSWORD)` expansion) so they never land in a ConfigMap. The schema requires `external.host` to be set whenever Redis is disabled.

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
  strategy: "hook" # default
```

| Strategy     | Behavior                                    | Use Case                      |
| ------------ | ------------------------------------------- | ----------------------------- |
| `hook`       | Runs as Helm post-install/post-upgrade hook | Standard deployments          |
| `deployment` | Creates job as regular resource             | When post-rendering is needed |
| `manual`     | Renders template without hooks              | Full control over execution   |

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
| **kube-prometheus-stack** | Metrics collection (Prometheus)                    |    ✓    |

---

<details>
<summary><strong>Deployment Troubleshooting</strong></summary>

### Retry Installation

```bash
helm uninstall rulebricks -n rulebricks
# Clear PVCs
kubectl delete pvc --all -n rulebricks
helm install rulebricks oci://ghcr.io/rulebricks/helm/stack -n rulebricks -f your-values.yaml
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
