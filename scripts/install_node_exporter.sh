#!/usr/bin/env bash
set -euo pipefail

# Installs Prometheus Node Exporter from the Ubuntu/Debian apt repository.
#
# The apt package (prometheus-node-exporter) ships its own systemd unit and is
# upgraded together with everything else by `sudo apt update && sudo apt
# upgrade`, so there is no pinned version to maintain. It listens on :9100.

if command -v prometheus-node-exporter &>/dev/null; then
    echo "prometheus-node-exporter is already installed:"
    prometheus-node-exporter --version 2>&1 | head -n 1 || true
else
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y prometheus-node-exporter
fi

sudo systemctl enable --now prometheus-node-exporter
sudo systemctl --no-pager --lines=0 status prometheus-node-exporter || true

echo ""
echo "Node Exporter metrics: http://$(hostname -I 2>/dev/null | awk '{print $1}'):9100/metrics"
