# Rulebricks Helm Chart

A production-ready Helm chart for deploying Rulebricks and its dependencies (Kafka, Supabase, Redis) on Kubernetes.

## Prerequisites

- **Kubernetes 1.19+**
- **Helm 3.2.0+**
- **Domain Name**: Pointed to your cluster's load balancer.
- **License Key**: A valid Rulebricks license key.

## Quick Start

### 1. Clone & Update Dependencies

```bash
git clone <repo-url>
cd helm
helm dependency update
```

### 2. Configure `values.yaml`

Edit `values.yaml` and set the following **required** fields:

```yaml
global:
  domain: "your-domain.com"
  email: "admin@your-domain.com" # Used for TLS certificates

rulebricks:
  app:
    licenseKey: "YOUR_LICENSE_KEY"
    email: "admin@your-domain.com"

    # Image Credentials (Required for private images)
    imageCredentials:
      password: "dckr_pat_YOUR_LICENSE_KEY" # Format: dckr_pat_<license-key>

    smtp:
      host: "smtp.your-provider.com"
      port: 587
      user: "smtp-user"
      pass: "smtp-password"

supabase:
  secret:
    jwt:
      # Generate secure random strings (min 32 chars)
      secret: "change-me-to-a-secure-random-string"
      anonKey: "generate-valid-jwt-using-secret-above"
      serviceKey: "generate-valid-jwt-using-secret-above"
    db:
      password: "secure-db-password"
    dashboard:
      password: "secure-dashboard-password"
    smtp:
      username: "smtp-user"
      password: "smtp-password"

  auth:
    environment:
      GOTRUE_SMTP_HOST: "smtp.your-provider.com"
      GOTRUE_SMTP_PORT: "587"
```

### 3. Install

```bash
helm install rulebricks . --namespace rulebricks --create-namespace
```

### 4. Verify

```bash
kubectl get pods -n rulebricks
```

Wait for all pods to reach `Running` state. The `rulebricks-db-migrate` job should complete successfully.

## Architecture

This chart deploys:

- **Rulebricks App**: The core application.
- **High Performance Solver (HPS)**: Scalable rule execution engine.
- **Supabase**: Embedded backend services (Auth, REST, Realtime, Postgres).
- **Kafka**: Message bus for HPS and logging.
- **Redis**: Ephemeral state and caching.
- **Traefik**: Ingress controller.
- **Cert-Manager**: Automatic TLS provisioning (Let's Encrypt).
- **KEDA**: Event-driven autoscaling for HPS workers.
- **Vector**: Log aggregation.

## Troubleshooting

### "CRD already exists" or "Resource mapping not found"

The CRDs are managed in the `crds/` directory. If you see CRD errors, uninstall and ensure you are using Helm 3, which installs `crds/` automatically.

### ImagePullBackOff

Ensure your `rulebricks.app.imageCredentials.password` is correct. It must be `dckr_pat_<YOUR_LICENSE_KEY>`.

### PVC Pending (Storage Issues)

Check your default storage class. The chart defaults to `gp2` (AWS). If you are on Azure/GCP or local, update the `storageClass` in `values.yaml` for `kafka`, `supabase.db`, and `redis`.

```yaml
redis:
  persistence:
    storageClass: standard # or default
```

### Database Migration Stuck

Check the migration job logs:

```bash
kubectl logs -l app.kubernetes.io/component=migrations -n rulebricks
```
