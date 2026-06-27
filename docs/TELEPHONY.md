# KNVOX V1.1.0 Telephony Foundation

## Services

- Kamailio : SIP Proxy / SBC
- RTPEngine : RTP media proxy
- FreeSWITCH : softswitch / media server

## Ports publics V1.1

- 5060/udp + 5060/tcp : Kamailio SIP
- 30000-40000/udp : RTP via RTPEngine

## FreeSWITCH

FreeSWITCH écoute localement sur 127.0.0.1:5070.
Il ne doit pas être exposé directement aux clients.

## Test SIP

Utilisateurs de test : 1000 à 1019.

Le mot de passe est dans le fichier .env, variable FS_DEFAULT_PASSWORD.

Numéro de test echo : 9996.

## Important

Ne pas connecter de fournisseur PSTN/minutes tant que la sécurité antifraude et le billing ne sont pas en place.
