#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================="
echo " KNVOX BILLING REPORTS TEST"
echo "===================================="

CUSTOMER="${1:-TEST1000}"
DATE_FROM="${2:-2026-01-01}"
DATE_TO="${3:-2026-12-31}"

echo ""
echo "[1/6] Usage report"
./scripts/report-usage.sh "${CUSTOMER}" "${DATE_FROM}" "${DATE_TO}"

echo ""
echo "[2/6] Margin report"
./scripts/report-margin.sh "${CUSTOMER}" "${DATE_FROM}" "${DATE_TO}"

echo ""
echo "[3/6] Wallet report"
./scripts/report-wallet.sh "${CUSTOMER}"

echo ""
echo "[4/6] CDR CSV export"
./scripts/report-cdr-csv.sh "${CUSTOMER}" "${DATE_FROM}" "${DATE_TO}"

echo ""
echo "[5/6] Invoice export"
./scripts/report-invoice-export.sh "${CUSTOMER}" "${DATE_FROM}" "${DATE_TO}"

echo ""
echo "[6/6] Invoice export list + health"
./scripts/report-invoice-list.sh
make health

echo ""
echo "Test Billing Reports terminé."
