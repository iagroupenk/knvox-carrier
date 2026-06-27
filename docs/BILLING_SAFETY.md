# KNVOX V1.3.4 - Billing Safety Layer

## Objectif

Cette version prépare le contrôle d'autorisation avant tout appel externe.

## Règles actives

- Client obligatoire
- Client actif obligatoire
- Solde suffisant obligatoire
- Préfixe tarifaire obligatoire
- Préfixes à risque bloqués
- Limite d'appels simultanés
- PSTN désactivé par défaut

## Comportement attendu

- Appel vers 9996 : autorisé
- Appel vers 1000 à 1019 : autorisé
- Appel vers fixe/mobile externe : refusé avec `pstn_disabled`
- Appel vers préfixe bloqué : refusé avec `blocked_prefix_xxx`

## Activation PSTN

Ne pas activer PSTN tant que les trunks fournisseurs, l'anti-fraude, les limites CPS et l'intégration Kamailio/FreeSWITCH ne sont pas validés.

Commande future, à ne pas lancer maintenant :

UPDATE billing.system_settings SET value='true' WHERE key='pstn_enabled';
