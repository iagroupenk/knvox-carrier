.RECIPEPREFIX := >
.PHONY: start stop restart status health logs backup pull update firewall

start:
>docker compose up -d

stop:
>docker compose down

restart:
>docker compose restart

status:
>./scripts/status.sh

health:
>./scripts/healthcheck.sh

logs:
>./scripts/logs.sh

backup:
>./scripts/backup.sh

pull:
>docker compose pull

update:
>docker compose pull
>docker compose up -d

firewall:
>./scripts/firewall.sh
