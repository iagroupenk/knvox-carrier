# KNVOX V1.5.2b - Duplicate INVITE Billing Fix

## Problème

Certains softphones renvoient plusieurs INVITE pour le même Call-ID.

Le premier INVITE est autorisé, puis le suivant peut être bloqué par les contrôles billing/fraud, ce qui affiche :

Billing Authorization Failed 403

## Correction

Le script Kamailio conserve temporairement les Call-ID déjà autorisés.

Si un INVITE identique revient avec le même Call-ID, même username, même source et même destination, il est accepté sans refaire un start-call billing.

## Log correct

logs/kamailio-auth/auth.log

## Sécurité

- PSTN toujours désactivé
- Aucun trunk réel connecté
- Le cache expire automatiquement après 180 secondes
