# KNVOX V1.4.3 - Customer Portal Frontend

## Objectif

Cette version ajoute un portail web interne pour consulter :

- statut plateforme
- clients
- soldes
- CDR
- rapports usage
- rapports marge
- wallet
- tarifs
- préfixes bloqués
- routes fournisseurs sandbox

## Sécurité

Le portail est exposé uniquement en local :

127.0.0.1:8090

Le navigateur ne connaît pas le token API.  
Nginx ajoute le header `X-KNVOX-API-Key` côté serveur via proxy local.

## Accès distant via tunnel SSH

Depuis ton ordinateur :

ssh -L 8090:127.0.0.1:8090 root@IP_DU_SERVEUR

Puis ouvrir :

http://127.0.0.1:8090

## Important

Ne pas exposer ce portail publiquement sans authentification forte.
Le PSTN reste désactivé.
