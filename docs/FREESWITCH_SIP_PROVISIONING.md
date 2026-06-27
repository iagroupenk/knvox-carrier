# KNVOX V1.5.1 - FreeSWITCH SIP Provisioning

## Objectif

Synchroniser les comptes SIP stockés dans `billing.sip_accounts` vers FreeSWITCH.

## Fonctionnement

La source de vérité devient :

billing.sip_accounts

Le script génère :

storage/telephony/freeswitch/conf/directory/default/knvox-db-sip-accounts.xml

Puis exécute :

reloadxml
sofia profile internal rescan

## Périmètre V1.5.1

Cette version provisionne les comptes SIP dans la plage déjà autorisée :

1000 à 1019

La future version pourra ouvrir dynamiquement d'autres plages SIP.

## Exports

Un CSV de provisioning est généré localement dans :

exports/sip/

Ce dossier est ignoré par Git car il contient des mots de passe SIP.

## Test softphone

Serveur SIP : IP publique du serveur  
Port : 5060 UDP  
Username : compte SIP, par exemple 1001  
Password : mot de passe généré dans l'API ou CSV local  
Numéro de test : 9996

## Sécurité

- PSTN désactivé
- Aucun trunk réel connecté
- CSV provisioning ignoré par Git
- API token non exposé au navigateur
