.RECIPEPREFIX := >
.PHONY: start stop restart status health logs backup pull update firewall telephony telephony-status fs sip-users firewall-telephony sip-security-test sip-security-logs billing billing-status billing-db-init billing-sample-data billing-cdr-test cgr-console

start:
>./scripts/compose.sh up -d

stop:
>./scripts/compose.sh down

restart:
>./scripts/compose.sh restart

status:
>./scripts/status.sh

health:
>./scripts/healthcheck.sh

logs:
>./scripts/logs.sh

backup:
>./scripts/backup.sh

pull:
>./scripts/compose.sh pull

update:
>./scripts/compose.sh pull
>./scripts/compose.sh up -d

firewall:
>./scripts/firewall.sh

telephony:
>./scripts/compose.sh up -d --build freeswitch rtpengine kamailio

telephony-status:
>./scripts/telephony-status.sh

fs:
>./scripts/fs_cli.sh

sip-users:
>./scripts/show-sip-users.sh

firewall-telephony:
>./scripts/firewall-telephony.sh

sip-security-test:
>./scripts/sip-security-test.sh

sip-security-logs:
>./scripts/sip-security-logs.sh

billing:
>./scripts/compose.sh up -d cgr-engine

billing-status:
>./scripts/billing-status.sh

billing-db-init:
>./scripts/billing-db-init.sh

billing-sample-data:
>./scripts/billing-sample-data.sh

billing-cdr-test:
>./scripts/billing-cdr-test.sh

cgr-console:
>./scripts/cgr-console.sh status
