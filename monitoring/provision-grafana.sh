#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/grafana/provisioning/dashboards"
mkdir -p "$OUT_DIR"

download_dashboard() {
  local gnet_id="$1"
  local revision="$2"
  local out_file="$OUT_DIR/gnet-${gnet_id}.json"

  if [[ -f "$out_file" ]]; then
    echo "Dashboard $gnet_id already exists, skip"
    return 0
  fi

  if [[ -z "$revision" ]]; then
    # try to get latest revision id
    revision=$(curl -fsS "https://grafana.com/api/dashboards/${gnet_id}" 2>/dev/null | jq -r '.dashboard.version' 2>/dev/null || true)
  fi

  if [[ -z "$revision" || "$revision" == "null" ]]; then
    echo "Could not determine revision for dashboard ${gnet_id}, attempting download without revision"
    curl -fsSL "https://grafana.com/api/dashboards/${gnet_id}/revisions" -o /tmp/gnet-${gnet_id}-revs.json || true
    revision=$(jq -r '.[0].revision' /tmp/gnet-${gnet_id}-revs.json 2>/dev/null || true)
  fi

  if [[ -n "$revision" && "$revision" != "null" ]]; then
    url="https://grafana.com/api/dashboards/${gnet_id}/revisions/${revision}/download"
  else
    url="https://grafana.com/api/dashboards/${gnet_id}/revisions/1/download"
  fi

  echo "Downloading dashboard ${gnet_id} revision ${revision}..."
  if curl -fsSL "$url" -o "$out_file"; then
    echo "Saved $out_file"
  else
    echo "Failed to download dashboard ${gnet_id}"
    return 1
  fi
}

if [[ $# -eq 0 ]]; then
  # default: download Node Exporter Full (gnetId 1860)
  download_dashboard 1860 ""
  exit 0
fi

while [[ $# -gt 0 ]]; do
  gnet="$1"; shift
  download_dashboard "$gnet" ""
done
