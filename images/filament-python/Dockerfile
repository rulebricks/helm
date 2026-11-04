# check=skip=InvalidDefaultArgInFrom
# Filament's local Python runtime. The base pin lives in images/manifest.yaml
# and is supplied by scripts/images/build.sh.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 MPLCONFIGDIR=/workspace/.matplotlib HOME=/workspace
COPY requirements.txt /opt/filament/requirements.txt
RUN pip install --no-cache-dir --requirement /opt/filament/requirements.txt \
    && mkdir -p /workspace /opt/filament \
    && chown 65532:65532 /workspace
COPY runner.py /opt/filament/runner.py
USER 65532:65532
WORKDIR /workspace
ENTRYPOINT ["python", "/opt/filament/runner.py", "serve"]
