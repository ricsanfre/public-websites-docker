#!/bin/bash

# Matomo mysql backup script

#Define a timestamp function
timestamp() {
date "+%b %d %Y %T %Z"
}

#Define load environment variables file function
envup() {
  local file=$1

  if [ -f $file ]; then
    set -a
    source $file
    set +a
  else
    echo "No $file file found" 1>&2
    return 1
  fi
}

MARIA_DB_DOCKER_COMPOSE_SERVICE=db
BACKUP_DIR=./matomo/backup
LOG=./backup.log
# Load matomo db environme variables file
envup ./matomo/db.env

# Add timestamp
echo "$(timestamp): Matmo-DB-backup started" | tee -a $LOG
echo "-------------------------------------------------------------------------------" | tee -a $LOG


# Execute Mysql dump command through docker-compose
docker-compose exec --no-TTY ${MARIA_DB_DOCKER_COMPOSE_SERVICE} mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --all-databases > ${BACKUP_DIR}/matomo-db-dump.sql 2>> $LOG

# Compress dump file
tar zcf ${BACKUP_DIR}/matomo-mysql-database-$(date +%Y-%m-%d-%H.%M.%S).sql.tar.gz ${BACKUP_DIR}/matomo-db-dump.sql

# Delete dump file
rm ${BACKUP_DIR}/matomo-db-dump.sql

# Delete old backup files
find ${BACKUP_DIR} -mtime +10 -exec rm {} \;

# Add timestamp
echo "-------------------------------------------------------------------------------" | tee -a $LOG
echo "$(timestamp): Matomo DB backup finished" | tee -a $LOG
printf "\n" | tee -a $LOG