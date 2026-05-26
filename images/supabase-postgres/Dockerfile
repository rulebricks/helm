FROM supabase/postgres:15.1.0.147

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
  && python3 -m venv /opt/barman-cloud \
  && /opt/barman-cloud/bin/pip install --no-cache-dir --upgrade pip \
  && /opt/barman-cloud/bin/pip install --no-cache-dir "barman[cloud,azure,google]" \
  && find /opt/barman-cloud/bin -maxdepth 1 -name "barman-cloud-*" -exec ln -sf {} /usr/local/bin/ \; \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER postgres
