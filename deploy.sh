#!/bin/bash
# deploy.sh — Sync canonical source to Omarchy plugin directory
#
# The Git repo (/home/roddy/Projects/Omarseafile/) is the source of truth.
# This script deploys plugin files to the Omarchy runtime location.
#
# Usage:
#   ./deploy.sh          # sync to default plugin dir
#   ./deploy.sh --check  # dry run, show what would change
#
# Excludes: .git/, docs/, README.md, deploy.sh, .gitignore

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/roddy.seafile}"

DRY_RUN=false
[[ "${1:-}" == "--check" ]] && DRY_RUN=true

echo "Source:  $REPO_DIR"
echo "Target:  $PLUGIN_DIR"

if $DRY_RUN; then
  echo "Mode:    DRY RUN (no changes)"
  echo ""
  rsync -avnc --delete \
    --exclude='.git/' \
    --exclude='docs/' \
    --exclude='README.md' \
    --exclude='deploy.sh' \
    --exclude='.gitignore' \
    "$REPO_DIR/" "$PLUGIN_DIR/"
  echo ""
  echo "Dry run complete. No files changed."
else
  mkdir -p "$PLUGIN_DIR"
  rsync -av --delete \
    --exclude='.git/' \
    --exclude='docs/' \
    --exclude='README.md' \
    --exclude='deploy.sh' \
    --exclude='.gitignore' \
    "$REPO_DIR/" "$PLUGIN_DIR/"
  echo ""
  echo "Deploy complete."
fi
