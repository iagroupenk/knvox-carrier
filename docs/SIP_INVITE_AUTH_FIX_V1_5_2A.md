# KNVOX V1.5.2a - SIP INVITE Billing Authorization Fix

## Problème

Certains softphones envoient plusieurs INVITE pendant le même appel.

Le premier INVITE est autorisé par le billing, puis un re-INVITE peut être bloqué par le Fraud Guard ou les limites CPS, ce qui provoque :

Billing Authorization Failed - 403

## Correction

Kamailio appelle le Billing Authorization uniquement sur l'INVITE initial.

Les INVITE in-dialog avec To-tag sont bypassés côté billing.

## Log correct

Le fichier host correct est :

logs/kamailio-auth/auth.log

## Sécurité

PSTN toujours désactivé.
Aucun trunk réel connecté.
