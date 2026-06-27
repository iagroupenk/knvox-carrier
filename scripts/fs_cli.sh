#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

docker exec -it knvox-freeswitch fs_cli -H 127.0.0.1 -P 8021 -p "$FS_EVENT_SOCKET_PASSWORD" "$@"
