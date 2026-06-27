# KNVOX V1.4.2 - Billing Reports & Invoice Export

## Objectif

Cette version ajoute les rapports billing nécessaires pour l'exploitation commerciale.

## Fonctions

- Rapport usage client
- Rapport marge estimée
- Export CDR CSV
- Ledger wallet / recharges
- Création d'un export facture interne
- Liste des exports de facture

## Endpoints

GET /api/v1/reports/customers/{customer_code}/usage

GET /api/v1/reports/customers/{customer_code}/margin

GET /api/v1/reports/customers/{customer_code}/wallet

GET /api/v1/reports/customers/{customer_code}/cdrs.csv

POST /api/v1/reports/customers/{customer_code}/invoice-export

GET /api/v1/reports/invoice-exports

## Important

Les marges sont estimées tant que les appels PSTN réels ne sont pas actifs.

Le PSTN reste désactivé.
