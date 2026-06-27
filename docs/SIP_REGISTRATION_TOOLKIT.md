# KNVOX V1.5.2 - SIP Registration Toolkit

Objectif : tester les comptes SIP avec un softphone ou un call center.

Commandes principales :

- make sip-reg-test
- SIP_USER=1002 make sip-card
- SIP_USER=1002 make sip-reg-check
- make sip-reg-status
- make sip-tools-install
- make sip-live-capture

Paramètres softphone :

- Serveur SIP : 51.222.115.82
- Port : 5060
- Transport : UDP
- Username : compte SIP, exemple 1002
- Password : affiché dans la fiche
- Numéro test : 9996

Sécurité :

- PSTN désactivé
- Aucun trunk réel connecté
- exports/sip ignoré par Git
