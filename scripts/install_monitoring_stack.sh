#!/usr/bin/env bash
set -euo pipefail

# Provisions the host-side Prometheus + Grafana stack.
#
# Every path derives from STACK_DIR, so the config file and the compose file
# cannot end up in different directories — the mismatch that previously left
# the Docker daemon creating a root-owned directory at the bind-mount source
# and runc refusing to mount a directory onto a file.

STACK_DIR="${STACK_DIR:-$HOME/monitoring/prometheus}"
PROM_IMAGE="prom/prometheus:latest"

die() { echo "Error: $*" >&2; exit 1; }

# ── Prerequisites ──────────────────────────────────────────────────────────────
command -v docker &>/dev/null || die "Docker is not installed. Install it first (unix-manager -> Unix Program Installer -> docker)."
docker compose version &>/dev/null || die "The Docker Compose plugin is missing. Install docker-compose-plugin."
command -v python3 &>/dev/null || die "python3 is required to verify scrape targets."

# The Grafana admin password is injected at run time and never written to a
# file. Set it in the environment or in $STACK_DIR/.env before running.
: "${GF_ADMIN_PASSWORD:?must be set (export it, or put it in \$STACK_DIR/.env) — it is deliberately never written into docker-compose.yml}"

echo "Stack directory: $STACK_DIR"
mkdir -p "$STACK_DIR"
cd "$STACK_DIR"

# ── Repair an earlier failed run ────────────────────────────────────────────────
# A mismatched mount source leaves behind a root-owned empty directory that the
# daemon created. sudo cannot prompt without a TTY, so remove it from inside a
# container; rmdir rather than rm -rf, so it only succeeds when truly empty.
if [ -d prometheus/prometheus.yml ]; then
    echo "Removing the stray root-owned directory left by an earlier failed run..."
    docker run --rm -v "$STACK_DIR:/mnt" alpine \
        sh -c 'rmdir /mnt/prometheus/prometheus.yml && rmdir /mnt/prometheus' \
        || die "Could not remove $STACK_DIR/prometheus — it is not empty. Inspect it by hand."
fi

# ── Prometheus config ──────────────────────────────────────────────────────────
# Never overwrite an existing config: it holds real target addresses.
if [ -f prometheus.yml ]; then
    echo "prometheus.yml already exists — left untouched."
else
    echo "Writing a prometheus.yml template..."
    cat > prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets:
          - 'VM1_IP:9100'
          - 'VM2_IP:9100'
          - 'VM3_IP:9100'
          - 'VM4_IP:9100'
EOF
fi

# ── Compose file ───────────────────────────────────────────────────────────────
# Generated, so safe to rewrite on every run. The heredoc delimiter is quoted so
# the ${...} placeholders reach the file intact and Compose resolves them at
# start-up from the environment or .env.
echo "Writing docker-compose.yml..."
cat > docker-compose.yml <<'EOF'
services:

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GF_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_ADMIN_PASSWORD:?set GF_ADMIN_PASSWORD in the environment or .env}
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

volumes:
  prometheus_data:
  grafana_data:
EOF

# ── Pre-flight checks ──────────────────────────────────────────────────────────
# Each of these catches a failure that has actually happened in practice.
echo "Pre-flight checks..."

[ -f prometheus.yml ] \
    || die "$STACK_DIR/prometheus.yml is not a regular file — the bind mount would fail."

! grep -qE 'VM[0-9]_IP' prometheus.yml \
    || die "prometheus.yml still contains VM_IP placeholders. Replace them with real host:9100 targets in $STACK_DIR/prometheus.yml, then re-run."

# The image entrypoint is /bin/prometheus, so promtool needs an explicit override.
docker run --rm --entrypoint promtool \
    -v "$STACK_DIR/prometheus.yml:/tmp/p.yml:ro" "$PROM_IMAGE" \
    check config /tmp/p.yml \
    || die "prometheus.yml is not a valid Prometheus config."

docker compose config -q || die "docker-compose.yml is not valid."

echo "  config file    OK"
echo "  no placeholders OK"
echo "  compose file   OK"

# ── Start ──────────────────────────────────────────────────────────────────────
echo "Starting the stack..."
docker compose up -d

# ── Verify ─────────────────────────────────────────────────────────────────────
# "Up" is not evidence: a container reports Up before Prometheus has parsed its
# config, and a valid config still tells us nothing about reachable exporters.
echo "Waiting for Prometheus to become ready..."
ready=""
for _ in $(seq 1 30); do
    if [ "$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:9090/-/ready || true)" = "200" ]; then
        ready=yes
        break
    fi
    sleep 2
done
[ -n "$ready" ] || die "Prometheus did not become ready. Check: cd $STACK_DIR && docker compose logs prometheus"

echo "Checking scrape targets (allowing one scrape interval)..."
python3 - <<'PY'
import json, sys, time, urllib.request

URL = "http://localhost:9090/api/v1/targets"

def targets():
    with urllib.request.urlopen(URL, timeout=5) as r:
        return json.load(r)["data"]["activeTargets"]

active = []
for _ in range(20):
    active = targets()
    if active and not any(t["health"] == "unknown" for t in active):
        break
    time.sleep(2)

if not active:
    sys.exit("Error: Prometheus reports no active targets at all.")

width = max(len(t["scrapeUrl"]) for t in active)
for t in active:
    print(f"  {t['scrapeUrl']:<{width}}  {t['health']:<7}  {t.get('lastError') or ''}".rstrip())

bad = [t for t in active if t["health"] != "up"]
if bad:
    sys.exit(f"Error: {len(bad)} of {len(active)} target(s) are not up (see lastError above).")
print(f"All {len(active)} target(s) up.")
PY

echo
echo "Prometheus  http://localhost:9090"
echo "Grafana     http://localhost:3000"
echo "Next: add the Prometheus data source in Grafana using http://prometheus:9090 (the container name, not localhost), then import dashboard 1860."
