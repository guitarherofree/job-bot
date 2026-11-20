#!/bin/bash
# One-time setup from source: builds Job Bot and installs it in Applications.
# After this, Job Bot updates itself from GitHub Releases (Job Bot › Check for Updates…).
#
# Usage:  bash Scripts/install.sh
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
bash Scripts/build_app.sh --install --skip-tests
echo ""
echo "All set. Job Bot is in Applications. It checks GitHub for updates by itself"
echo "(Job Bot › Check for Updates…)."
