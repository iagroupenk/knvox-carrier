#!/bin/bash
set -euo pipefail

apt-get update
apt-get install -y sngrep tcpdump ngrep

echo "Outils SIP installés."
