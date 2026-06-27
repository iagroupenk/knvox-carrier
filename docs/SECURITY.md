# KNVOX Security Notes

## Ports publics V1

- 22/tcp SSH
- 80/tcp HTTP
- 443/tcp HTTPS

Les services internes ne doivent pas être exposés directement.

## Secrets

Le fichier .env contient les mots de passe.
Il doit rester local au serveur.

## Firewall

Pour activer UFW avec SSH sur le port 22 :

./scripts/firewall.sh

Si SSH utilise un autre port :

SSH_PORT=2222 ./scripts/firewall.sh
