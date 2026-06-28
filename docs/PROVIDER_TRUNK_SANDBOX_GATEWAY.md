# KNVOX V1.6.0 - Provider Trunk Sandbox Gateway

## Objectif

Préparer la couche trunks fournisseurs sans activer de vrai trafic PSTN.

## Ce que fait cette version

- Ajoute `billing.provider_trunks`
- Ajoute un registre de trunks fournisseurs sandbox
- Génère un fichier FreeSWITCH gateway volontairement désactivé
- Exporte un CSV local dans `exports/trunks/`
- Vérifie que `pstn_enabled=false`

## Fichier FreeSWITCH généré

storage/telephony/freeswitch/conf/sip_profiles/external/knvox-provider-gateways.generated.xml.disabled

Le fichier reste en `.disabled`.

FreeSWITCH ne le charge pas.

## Sécurité

- PSTN désactivé
- Aucun trunk réel connecté
- Aucun appel externe réel ne sort
- Les exports contenant des paramètres trunk sont ignorés par Git

## Commandes

make provider-trunk-sandbox-test
make provider-trunk-list
make provider-trunk-generate
make provider-trunk-events

## Activation réelle future

Avant de renommer le fichier `.disabled` en `.xml`, il faudra :

1. valider le provider réel
2. définir IP allowlist fournisseur
3. valider les tarifs buy/sell
4. activer les limites CPS/concurrent
5. activer le débit wallet
6. activer `pstn_enabled=true` seulement après validation
