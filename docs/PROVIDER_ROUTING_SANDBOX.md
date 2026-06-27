# KNVOX V1.3.9 - Provider Routing Sandbox

## Objectif

Préparer le routage fournisseur sans connecter de trunk réel.

## Fonctionnalités

- Fournisseurs sandbox
- Routes fournisseurs fictives
- Simulation prix d'achat
- Simulation prix de vente
- Calcul marge
- Journalisation des décisions de routage

## Sécurité

Le champ `trunk_enabled` reste à false.

Le paramètre global `pstn_enabled` reste à false.

Aucun appel externe ne doit sortir vers un fournisseur réel dans cette version.

## Endpoints

POST /api/v1/provider-route-simulate

GET /api/v1/provider-routes

## Comportement attendu

- 9996 : internal_no_provider
- 33612345678 : pstn_disabled_sandbox_route_found
- 882123456 : blocked_prefix_882
