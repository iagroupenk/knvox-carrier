#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p logs/kamailio-auth
touch logs/kamailio-auth/auth.log

echo "Tail : logs/kamailio-auth/auth.log"
tail -F logs/kamailio-auth/auth.log
