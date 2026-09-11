#!/usr/bin/env bash
set -euo pipefail

# Reports the state of the host-side monitoring stack: which prerequisites are
# present, where the stack actually lives, which containers run, and whether
# Prometheus and Grafana are genuinely healthy.
#
# Read-only by contract. It never writes, never uses sudo, and never starts or
# installs anything — absent pieces are reported, not fixed.
#
# The stack is discovered from Docker rather than from STACK_DIR. The running
# containers are the only authority on where the live config is: a stack
# provisioned by hand, or with STACK_DIR overridden, is invisible to a
# path-based check, and reporting "not installed" while it is plainly up is
# worse than not reporting at all. For the same reason the config path comes
# from the container's bind mount and the ports from `docker port`, so an
# overridden mapping is shown rather than assumed.

STACK_DIR="${STACK_DIR:-$HOME/monitoring/prometheus}"

section() { printf "\n%s\n" "$1"; }
row()     { printf "  %-18s%s\n" "$1" "$2"; }
cont()    { printf "  %-18s%s\n" "" "$1"; }

# Summarises /api/v1/targets read from stdin. Kept as a function over stdin so
# it can be exercised against a fixture without a live Prometheus.
TARGETS_PY='
import json, re, sys

try:
    data = json.load(sys.stdin)
except Exception as exc:
    print("unreadable response (%s)" % exc)
    sys.exit(0)

active = data.get("data", {}).get("activeTargets", [])
if not active:
    print("none configured")
    sys.exit(0)

up = [t for t in active if t.get("health") == "up"]
print("%d of %d up" % (len(up), len(active)))


def target(t):
    # host:port is what identifies an exporter; the scheme and the conventional
    # /metrics path are noise repeated on every line.
    url = re.sub("^https?://", "", t.get("scrapeUrl", ""))
    return re.sub("/metrics$", "", url)


def cause(t):
    # Prometheus restates the target URL and the dial address in lastError, both
    # of which are already in the first column. Keep only the cause.
    err = t.get("lastError") or t.get("health") or ""
    for noise in ("^Get \"[^\"]*\": ", "^dial tcp [^ ]+: ", "^connect: "):
        err = re.sub(noise, "", err)
    return err


bad = [t for t in active if t.get("health") != "up"]
width = max((len(target(t)) for t in bad), default=0)
for t in bad:
    print("%-*s  %s" % (width, target(t), cause(t)))
'
summarise_targets() { python3 -c "$TARGETS_PY"; }

find_container() {   # $1 = image prefix, e.g. prom/prometheus
    docker ps -a --format '{{.ID}}|{{.Image}}|{{.Names}}' 2>/dev/null \
        | awk -F'|' -v p="$1" 'index($2, p) == 1 { print $1; exit }'
}
label_of()  { docker inspect -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null || true; }
is_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" == "true" ]]; }
host_port() { docker port "$1" "$2" 2>/dev/null | head -1 | awk -F: '{print $NF}'; }

echo "Monitoring (on host) — status"

# ── Prerequisites ──────────────────────────────────────────────────────────────
section "Prerequisites"

if command -v docker &>/dev/null; then
    row "docker" "$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo present)"
else
    row "docker" "not installed"
    cont "install it with: unix-manager -> Unix Program Installer -> docker"
    exit 1
fi

if docker compose version &>/dev/null; then
    row "compose plugin" "$(docker compose version --short 2>/dev/null || echo present)"
else
    row "compose plugin" "not installed (docker-compose-plugin)"
fi

if command -v prometheus-node-exporter &>/dev/null; then
    ne_ver=$(prometheus-node-exporter --version 2>&1 | head -1 | awk '{print $3}' || true)
    ne_state=$(systemctl is-active prometheus-node-exporter 2>/dev/null || true)
    row "node exporter" "${ne_ver:-installed}${ne_state:+  ($ne_state)}"
else
    row "node exporter" "not installed (host)"
fi

if ! docker ps -q &>/dev/null; then
    section "Stack"
    row "docker daemon" "not reachable — cannot inspect the stack"
    exit 1
fi

prom_id=$(find_container "prom/prometheus" || true)
graf_id=$(find_container "grafana/grafana" || true)

# ── Stack ──────────────────────────────────────────────────────────────────────
section "Stack"

if [[ -z "$prom_id" ]]; then
    row "compose project" "no Prometheus container found"
    if [[ -d "$STACK_DIR" ]]; then
        row "directory" "$STACK_DIR (present, nothing running)"
    else
        row "directory" "$STACK_DIR (absent)"
        cont "provision it with: Monitoring (on host) -> install stack"
    fi
else
    project=$(label_of "$prom_id" com.docker.compose.project)
    workdir=$(label_of "$prom_id" com.docker.compose.project.working_dir)
    row "compose project" "${project:-none (not compose-managed)}"
    row "directory" "${workdir:-unknown}"

    # The bind mount source is the file Prometheus actually reads.
    cfg=$(docker inspect \
        -f '{{range .Mounts}}{{if eq .Destination "/etc/prometheus/prometheus.yml"}}{{.Source}}{{end}}{{end}}' \
        "$prom_id" 2>/dev/null || true)
    row "config" "${cfg:-not bind-mounted (baked into the image)}"

    if [[ -n "$cfg" && -r "$cfg" ]]; then
        if grep -qE 'VM[0-9]_IP' "$cfg"; then
            row "config check" "VM_IP placeholders still present — scrapes will fail"
        else
            row "config check" "no placeholders"
        fi
    fi

    retention=$(docker inspect -f '{{range .Config.Cmd}}{{println .}}{{end}}' "$prom_id" 2>/dev/null \
        | sed -n 's/^--storage\.tsdb\.retention\.time=//p' | head -1 || true)
    row "retention" "${retention:-not set (Prometheus default, 15d)}"

    # A stack somewhere other than STACK_DIR is fine, but `install stack` would
    # build a second one at the default path rather than touch this one.
    if [[ -n "$workdir" && "$workdir" != "$STACK_DIR" ]]; then
        cont "note: STACK_DIR default is $STACK_DIR"
        cont "      'install stack' would provision a second stack there"
    fi
fi

# ── Containers ─────────────────────────────────────────────────────────────────
section "Containers"

show_container() {   # $1 = container id, $2 = label when absent
    local id="$1" absent="$2" name status ports
    if [[ -z "$id" ]]; then
        row "$absent" "not present"
        return
    fi
    name=$(docker inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##' || echo "$absent")
    status=$(docker ps -a --filter "id=$id" --format '{{.Status}}' 2>/dev/null || true)
    ports=$(docker port "$id" 2>/dev/null | awk -F' -> ' 'NF==2 {print $2}' \
        | awk -F: '{print ":"$NF}' | sort -u | paste -sd, - || true)
    row "$name" "$(printf '%-16s%s' "${status:-unknown}" "$ports")"
}

show_container "$prom_id" "prometheus"
show_container "$graf_id" "grafana"

# ── Health ─────────────────────────────────────────────────────────────────────
# "Up" is not evidence: a container reports Up before Prometheus has parsed its
# config, and a parsed config still says nothing about reachable exporters.
section "Health"

if [[ -n "$prom_id" ]] && is_running "$prom_id"; then
    pport=$(host_port "$prom_id" 9090/tcp); pport="${pport:-9090}"
    code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 3 \
        "http://localhost:$pport/-/ready" 2>/dev/null || true)
    if [[ "$code" == "200" ]]; then
        row "prometheus" "ready"
        mapfile -t tlines < <(curl -fsS --max-time 5 \
            "http://localhost:$pport/api/v1/targets" 2>/dev/null | summarise_targets || true)
        row "targets" "${tlines[0]:-unreachable}"
        for line in "${tlines[@]:1}"; do cont "$line"; done
    else
        # curl reports 000 when it could not connect at all, which is not a
        # status code and should not be shown as one.
        if [[ -z "$code" || "$code" == "000" ]]; then
            row "prometheus" "not responding on port $pport"
        else
            row "prometheus" "not ready (HTTP $code)"
        fi
        cont "logs: cd ${workdir:-$STACK_DIR} && docker compose logs prometheus"
    fi
else
    row "prometheus" "not running"
fi

if [[ -n "$graf_id" ]] && is_running "$graf_id"; then
    gport=$(host_port "$graf_id" 3000/tcp); gport="${gport:-3000}"
    health=$(curl -fsS --max-time 3 "http://localhost:$gport/api/health" 2>/dev/null || true)
    if [[ -n "$health" ]]; then
        row "grafana" "$(printf '%s' "$health" | python3 -c \
            'import json,sys; d=json.load(sys.stdin); print("database %s, version %s" % (d.get("database","?"), d.get("version","?")))' \
            2>/dev/null || echo responding)"
    else
        row "grafana" "not responding"
    fi
else
    row "grafana" "not running"
fi

echo
