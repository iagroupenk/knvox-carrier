#!/bin/bash
set -e

cd "$(dirname "$0")/.."

set -a
source .env
set +a

echo "===================================="
echo " KNVOX SIP TEST USERS"
echo "===================================="
echo ""
echo "SIP Server : ${SIP_DOMAIN}"
echo "SIP Port   : ${KAMAILIO_SIP_PORT}"
echo "Transport  : UDP ou TCP"
echo ""
echo "Utilisateurs de test FreeSWITCH :"
echo "1000 à 1019"
echo ""
echo "Mot de passe SIP :"
echo "${FS_DEFAULT_PASSWORD}"
echo ""
echo "Test echo : appeler 9996"
echo ""
echo "Important : ne connecte pas encore de fournisseur minutes/PSTN."
