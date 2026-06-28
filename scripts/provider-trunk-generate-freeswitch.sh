#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source .env
set +a

OUT="storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml.disabled"
EXPORT="exports/trunks/provider_trunks_$(date +%Y%m%d-%H%M%S).csv"

mkdir -p "$(dirname "$OUT")" exports/trunks

TMP="$(mktemp)"

./scripts/compose.sh exec -T postgres psql \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -AtF $'\t' <<'SQL' > "$TMP"
SELECT
  provider_code,
  trunk_name,
  sip_host,
  sip_port,
  transport,
  COALESCE(auth_username, ''),
  COALESCE(auth_password, ''),
  COALESCE(from_domain, sip_host),
  register,
  enabled,
  sandbox_only
FROM billing.provider_trunks
ORDER BY provider_code;
SQL

python3 - "$TMP" "$OUT" "$EXPORT" <<'PY'
import sys
import html
from pathlib import Path

tmp = Path(sys.argv[1])
out = Path(sys.argv[2])
export = Path(sys.argv[3])

rows = []
for line in tmp.read_text().splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    while len(parts) < 11:
        parts.append("")
    rows.append(parts[:11])

xml = []
xml.append("<include>")
xml.append("  <!-- KNVOX generated sandbox provider gateways. -->")
xml.append("  <!-- File intentionally .disabled : FreeSWITCH does NOT load this file. -->")
xml.append("  <!-- Do not rename to .xml until PSTN activation procedure is approved. -->")

csv = ["provider_code,trunk_name,sip_host,sip_port,transport,auth_username,auth_password,from_domain,register,enabled,sandbox_only"]

for r in rows:
    provider, name, host, port, transport, user, password, domain, register, enabled, sandbox = r

    p = html.escape(provider)
    h = html.escape(host)
    d = html.escape(domain or host)
    u = html.escape(user)
    pw = html.escape(password)
    tr = html.escape(transport or "udp")

    xml.append(f'  <gateway name="{p}">')
    xml.append(f'    <param name="proxy" value="{h}:{port}"/>')
    xml.append(f'    <param name="realm" value="{d}"/>')
    if u:
        xml.append(f'    <param name="username" value="{u}"/>')
    if pw:
        xml.append(f'    <param name="password" value="{pw}"/>')
    xml.append(f'    <param name="register" value="{str(register).lower()}"/>')
    xml.append(f'    <param name="extension" value="{p}"/>')
    xml.append(f'    <param name="context" value="public"/>')
    xml.append(f'    <param name="caller-id-in-from" value="true"/>')
    xml.append(f'    <!-- transport={tr} enabled={enabled} sandbox_only={sandbox} -->')
    xml.append("  </gateway>")

    def q(v):
        return '"' + str(v).replace('"', '""') + '"'
    csv.append(",".join(q(x) for x in r))

xml.append("</include>")
out.write_text("\n".join(xml) + "\n")
export.write_text("\n".join(csv) + "\n")
PY

chmod 600 "$OUT" "$EXPORT"
rm -f "$TMP"

echo "XML sandbox généré : $OUT"
echo "CSV local généré   : $EXPORT"
echo ""
echo "IMPORTANT : fichier .disabled, aucun trunk réel n'est chargé par FreeSWITCH."
