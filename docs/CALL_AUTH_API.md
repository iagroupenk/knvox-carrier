# KNVOX V1.3.5 - Call Authorization API

## Objectif

Cette API interne permet de demander une autorisation avant de router un appel.

Elle interroge PostgreSQL et utilise la fonction :

billing.authorize_call(customer_code, src, dst, call_id)

## Sécurité

L'API est exposée uniquement en local :

127.0.0.1:8088

Elle nécessite le header :

X-KNVOX-API-Key

Le token est stocké dans le fichier .env :

BILLING_API_TOKEN

## Endpoints

GET /health

POST /api/v1/authorize-call

GET /api/v1/status

## Exemple de réponse

allowed=false
reason=pstn_disabled

Cela signifie que le numéro a un tarif, que le client a du solde, mais que la sortie PSTN est volontairement désactivée.

## Important

Ne pas connecter de fournisseur PSTN tant que Kamailio ou FreeSWITCH n'appelle pas cette API avant chaque appel externe.
