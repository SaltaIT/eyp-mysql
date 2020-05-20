#!/bin/bash

function initbck
{
  if [ -z "${DESTINATION}" ];
  then
    echo "no destination defined"
    BCKFAILED=1
  else
    mkdir -p "$DESTINATION"
    BACKUPTS=$(date +%Y%m%d%H%M)

    if [ -z "${LOGDIR}" ];
    then
      LOG_FILE_PRESENT=0
      LOGDIR=$DESTINATION
      CURRENTBACKUPLOG="$LOGDIR/$BACKUPTS.log"
      exec 2>&1
    else
      LOG_FILE_PRESENT=1
      mkdir -p "$LOGDIR"
      CURRENTBACKUPLOG="$LOGDIR/$BACKUPTS.log"
      exec >> "$CURRENTBACKUPLOG" 2>&1
    fi

    BCKFAILED=0
  fi
}

function mailer
{
  MAILCMD=$(command -v mail 2>/dev/null)
  if [ -z "$MAILCMD" ];
  then
    echo "mail not found, skipping"
  else
    if [ -z "$MAILTO" ];
    then
      echo "mail skipped, no MAILTO defined"
      exit $BCKFAILED
    else
      if [ "${LOG_FILE_PRESENT}" -eq 0 ];
      then
        if [ "$BCKFAILED" -eq 0 ];
        then
          echo "OK" | "$MAILCMD" -s "$IDHOST-${BACKUP_NAME_ID}-OK" "$MAILTO"
        else
          echo "ERROR - no log file configured" | "$MAILCMD" -s "$IDHOST-${BACKUP_NAME_ID}-ERROR" "$MAILTO"
        fi
      else
        if [ "$BCKFAILED" -eq 0 ];
        then
          "$MAILCMD" -s "$IDHOST-${BACKUP_NAME_ID}-OK" "$MAILTO" < $CURRENTBACKUPLOG
        else
          "$MAILCMD" -s "$IDHOST-${BACKUP_NAME_ID}-ERROR" "$MAILTO" < $CURRENTBACKUPLOG
        fi
      fi
    fi
  fi
}

function dump_grants
{
  GRANTSDEST="$DESTINATION/$BACKUPTS"
  mkdir -p $GRANTSDEST

  GRANTSDESTFILE="$GRANTSDEST/${IDHOST}.grants.sql"

  echo "SELECT DISTINCT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') FROM mysql.user" | "$MYSQLBIN" ${MYSQL_INSTANCE_OPTS} -N | "$MYSQLBIN" ${MYSQL_INSTANCE_OPTS} -N 2>/dev/null | sed 's/$/;/' > "$GRANTSDESTFILE"

  if [[ ! -s "$GRANTSDESTFILE" ]];
  then
    echo "grants.sql not created or empty"
    BCKFAILED=1
  fi
}

function dodump
{
  MYSQLDUMP_BASEOPTS=${MYSQLDUMP_BASEOPTS-"--opt --routines -E --master-data=$MASTERDATA"}

  CURRENTBACKUPLOGDUMPERR="${DUMPDESTFILE}.err"

  if [ -n "${COMPRESS}" ] && [ "${COMPRESS}" -eq 1 ];
  then
    DUMPDESTFILE="${DUMPDESTFILE}.gz"
    "$MYSQLDUMPBIN" $MYSQLDUMP_BASEOPTS $MYSQLDUMP_EXTRAOPTS --databases $1 2> ${CURRENTBACKUPLOGDUMPERR} | gzip -9 > "$DUMPDESTFILE"
  else
    echo "compress skipped, standard dump"
    "$MYSQLDUMPBIN" $MYSQLDUMP_BASEOPTS $MYSQLDUMP_EXTRAOPTS --databases $1 > $DUMPDESTFILE 2> ${CURRENTBACKUPLOGDUMPERR}
  fi


  if [ "$?" -ne 0 ];
  then
    echo "mysqldump error, check logs"
    BCKFAILED=1
  fi

  if [ ! -z "$(cat ${CURRENTBACKUPLOGDUMPERR})" ];
  then
    echo "mysqldump error, check log ${CURRENTBACKUPLOGDUMPERR}"
    BCKFAILED=1
  fi

  if [[ ! -s "$DUMPDESTFILE" ]];
  then
    echo "dump empty or not found, check logs"
    BCKFAILED=1
  fi
}

function mysqldump
{
  MYSQL_VER=$(echo "select version()" | $MYSQLBIN ${MYSQL_INSTANCE_OPTS} -NB 2>/dev/null)

  if [ $? -ne 0 ];
  then
    echo "ERROR - mysql not available"
    BCKFAILED=1
  else
    echo "MySQL ${MYSQL_VER}"
  fi

  DUMPDEST="$DESTINATION/$BACKUPTS"

  mkdir -p $DUMPDEST

  DBS=${DBS-$(echo show databases | $MYSQLBIN ${MYSQL_INSTANCE_OPTS} -N  | grep -vE "^(information|performance)_schema$|^mysql$|^sys$`echo $EXCLUDED_DBS`")}

  MASTERDATA=${MASTERDATA-1}

  if [ -z "$DBS" ];
  then
    echo "no dbs found"
    BCKFAILED=1
  else
    if [ -z "${FILE_PER_DB}" ];
    then
      DUMPDESTFILE="$DUMPDEST/${IDHOST}.all.databases.sql"
      dodump $DBS
    else
      for EACHDB in $DBS;
      do
        EACHDB_FILE=$(echo "${EACHDB}" | sed 's/[^a-z0-9]/_/ig')
        DUMPDESTFILE="$DUMPDEST/${IDHOST}.${EACHDB_FILE}.sql"
        dodump $EACHDB
      done
    fi
  fi
}

function cleanup
{
  if [ -z "$RETENTION" ];
  then
    echo "cleanup skipped, no RETENTION defined"
  else
    find $DESTINATION -type f -mtime +$RETENTION -delete
    find $DESTINATION -type d -empty -delete
  fi
}

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"

BASEDIRBCK=$(dirname $0)
BASENAMEBCK=$(basename $0)

if [ ! -z "${INSTANCE_NAME}" ];
then
  MYSQL_INSTANCE_OPTS="--defaults-file=/etc/mysql/${INSTANCE_NAME}/my.cnf"
fi

if [ ! -z "$1" ] && [ -f "$1" ];
then
  . $1 2>/dev/null
else
  if [[ -s "$BASEDIRBCK/${BASENAMEBCK%%.*}.config" ]];
  then
    . $BASEDIRBCK/${BASENAMEBCK%%.*}.config 2>/dev/null
  else
    echo "config file missing"
    BCKFAILED=1
  fi
fi

IDHOST=${IDHOST-$(hostname -s)}
BACKUP_NAME_ID=${BACKUP_NAME_ID-MySQL}

MYSQLBIN=${MYSQLBIN-$(command -v mysql 2>/dev/null)}
if [ -z "$MYSQLBIN" ];
then
  echo "mysql not found"
  BCKFAILED=1
fi

MYSQLDUMPBIN=${MYSQLDUMPBIN-$(command -v mysqldump 2>/dev/null)}
if [ -z "$MYSQLDUMPBIN" ];
then
  echo "mysqldump not found"
  BCKFAILED=1
fi

VERSIOMYSQL=$(echo 'select version();' | $MYSQLBIN ${MYSQL_INSTANCE_OPTS} -N)

if [ "$?" -ne 0 ];
then
  echo "error connecting to MySQl"
  BCKFAILED=1
fi

# FORMAT EXCLUDED DBS

if [ ! -z $EXCLUDE ];
then
  for i in "${EXCLUDE[@]}";
  do
    EXCLUDED_DBS="$EXCLUDED_DBS|^$i$"
  done
fi

#
#
#

initbck

if [ "$BCKFAILED" -ne 1 ];
then
  date
  echo GRANTS
  dump_grants
  date
  echo DUMP
  mysqldump
  date
fi

mailer
cleanup
