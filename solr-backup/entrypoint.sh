#!/bin/bash

BACKUP_COMMAND="/var/solr-backup/backup-solr.sh"

if [[ -z "${CRON_SCHEDULE}" ]]; then
    CRON_SCHEDULE='0 0 * * * $BACKUP_COMMAND'
fi

CRON_SCHEDULE="${CRON_SCHEDULE//\$BACKUP_COMMAND/$BACKUP_COMMAND}"
echo "$CRON_SCHEDULE" > "/var/solr-backup/crontab"

exec /usr/local/bin/supercronic -passthrough-logs -quiet "/var/solr-backup/crontab"
