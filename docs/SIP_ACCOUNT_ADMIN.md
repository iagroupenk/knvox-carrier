# KNVOX V1.4.5 - SIP Account Admin

## Objectif

Créer une couche d'administration des comptes SIP liés aux clients call center.

## Fonctionnalités

- Création compte SIP
- Génération mot de passe SIP
- Association compte SIP -> customer_code
- Activation / désactivation
- Liste globale
- Liste par client
- Affichage dans le portail
- Journalisation des actions

## Important

Cette version ne modifie pas encore le routage Kamailio.

Kamailio continue d'autoriser les appels avec le client de test `TEST1000`.

La future version connectera les comptes SIP au call control multi-client.

## Sécurité

Le PSTN reste désactivé.

Aucun trunk fournisseur réel ne doit être connecté.
