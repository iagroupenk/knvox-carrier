.RECIPEPREFIX := >
.PHONY: fraud-status fraud-test fraud-lock-customer fraud-unlock-customer  start stop restart status health logs backup pull update firewall telephony telephony-status fs sip-users firewall-telephony sip-security-test sip-security-logs billing billing-status billing-db-init billing-sample-data billing-cdr-test cgr-console billing-safety-init billing-authorize billing-balance billing-rate-check billing-safety-test api api-status api-auth-test call-control call-control-test call-lifecycle call-lifecycle-test billing-cleanup-active provider-routing provider-routes provider-route-test customer-admin customer-admin-test customer-list customer-create customer-show customer-credit customer-limits customer-status customer-fraud-lock customer-cdrs rate-admin rate-admin-test rate-list rate-upsert rate-disable blocked-prefix-list blocked-prefix-add blocked-prefix-delete provider-route-upsert billing-reports billing-reports-test report-usage report-margin report-wallet report-cdr-csv report-invoice-export report-invoice-list

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

billing-safety-init:
>./scripts/billing-safety-init.sh

billing-authorize:
>./scripts/billing-authorize.sh

billing-balance:
>./scripts/billing-balance.sh

billing-rate-check:
>./scripts/billing-rate-check.sh

billing-safety-test:
>./scripts/billing-safety-test.sh

api:
>./scripts/compose.sh up -d --build billing-api

api-status:
>./scripts/api-status.sh

api-auth-test:
>./scripts/api-auth-test.sh

call-control:
>./scripts/compose.sh up -d --build billing-api kamailio

call-control-test:
>./scripts/call-control-test.sh

call-lifecycle:
>./scripts/compose.sh up -d --build billing-api kamailio

call-lifecycle-test:
>./scripts/api-lifecycle-test.sh

billing-cleanup-active:
>./scripts/billing-cleanup-active.sh


fraud-status:
>./scripts/fraud-status.sh

fraud-test:
>./scripts/fraud-test.sh

fraud-lock-customer:
>./scripts/fraud-lock-customer.sh

fraud-unlock-customer:
>./scripts/fraud-unlock-customer.sh


provider-routing:
>./scripts/compose.sh up -d --build billing-api

provider-routes:
>./scripts/provider-routes.sh

provider-route-test:
>./scripts/provider-route-test.sh


customer-admin:
>./scripts/compose.sh up -d --build billing-api

customer-admin-test:
>./scripts/customer-admin-test.sh

customer-list:
>./scripts/customer-list.sh

customer-create:
>./scripts/customer-create.sh

customer-show:
>./scripts/customer-show.sh

customer-credit:
>./scripts/customer-credit.sh

customer-limits:
>./scripts/customer-limits.sh

customer-status:
>./scripts/customer-status.sh

customer-fraud-lock:
>./scripts/customer-fraud-lock.sh

customer-cdrs:
>./scripts/customer-cdrs.sh


rate-admin:
>./scripts/compose.sh up -d --build billing-api

rate-admin-test:
>./scripts/rate-admin-test.sh

rate-list:
>./scripts/rate-list.sh

rate-upsert:
>./scripts/rate-upsert.sh

rate-disable:
>./scripts/rate-disable.sh

blocked-prefix-list:
>./scripts/blocked-prefix-list.sh

blocked-prefix-add:
>./scripts/blocked-prefix-add.sh

blocked-prefix-delete:
>./scripts/blocked-prefix-delete.sh

provider-route-upsert:
>./scripts/provider-route-upsert.sh


billing-reports:
>./scripts/compose.sh up -d --build billing-api

billing-reports-test:
>./scripts/billing-reports-test.sh

report-usage:
>./scripts/report-usage.sh

report-margin:
>./scripts/report-margin.sh

report-wallet:
>./scripts/report-wallet.sh

report-cdr-csv:
>./scripts/report-cdr-csv.sh

report-invoice-export:
>./scripts/report-invoice-export.sh

report-invoice-list:
>./scripts/report-invoice-list.sh
