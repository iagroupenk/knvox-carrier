#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs/kamailio-auth
touch logs/kamailio-auth/register-guard.log
tail -F logs/kamailio-auth/register-guard.log
