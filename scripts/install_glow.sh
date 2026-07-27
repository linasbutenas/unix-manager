#!/usr/bin/env bash
set -euo pipefail

echo "Installing glow (Charm)..."

# glow is not in the default Ubuntu repos — add the Charm apt repository.
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
sudo chmod a+r /etc/apt/keyrings/charm.gpg

echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    | sudo tee /etc/apt/sources.list.d/charm.list

sudo apt update
sudo apt install -y glow

echo "glow installed. Verifying..."
glow --version
echo "Done."
