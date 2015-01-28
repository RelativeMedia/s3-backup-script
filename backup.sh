#!/bin/bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source ${DIR}/backup.cfg

GREEN="\033[0;32m" 
RED="\033[0;31m"
RESET="\033[0m"

sendMail(){
  msg='{
  "async": false,
  "key": "'$MANDRILLKEY'",
  "message": {
    "from_email": "'$FROMEMAIL'",
    "from_name": "'$FROMNAME'",
    "return_path_domain": null,
    "subject": "['$HOSTNAME'] '$1'",
    "text": "'$2'",'

  if [ -n "$3" ]; then
  msg+='
    "attachments": [
      {
        "type": "text/plain",
        "name": "backup_report.txt",
        "content": "'$3'"
      }
    ],'
  fi
  msg+='
    "to": [
      {
        "email": "'$SENDTOEMAIL'",
        "type": "to"
      }
    ]
   }
  }'
	
	results=$(curl -A 'Mandrill-Curl/1.0' -d "$msg" 'https://mandrillapp.com/api/1.0/messages/send.json' -s 2>&1);
  echo "$results" | grep "sent" -q;
  if [ $? -ne 0 ]; then
		echo "An error occured: $results";
	fi
}

log() {
	echo -e "${RESET}[$(date)] -${GREEN} ${*}${RESET}" >> "${LogDir}/run.log"
}

error() {
	echo -e "${RESET}[$(date)] -${RED} ${*}${RESET}" >> "${LogDir}/error.log"
}

## Check we can write to the backups directory
if [ ! -d "$TmpBackupDir" ]
then
    mkdir -p $TmpBackupDir
else
    if [ -w "$TmpBackupDir" ]
    then
        # Do nothing and move along.
        log 'Found and is writable:  '$TmpBackupDir
    else
        error "Can't write to: "$TmpBackupDir
        sendMail "Backup Error" "Can't write to: $TmpBackupDir"
        exit
    fi
fi


## Backup the OS files
log 'Beginning to backup OS Files'
tar -cf "$TmpBackupDir/$FileBackupName.tar" --files-from /dev/null
for item  in "${filesToBackup[@]}"
do
    log "Backing up $item to $TmpBackupDir/$FileBackupName.tar.gz"
    tar -pPrf "$TmpBackupDir/$FileBackupName.tar" "$item"
done
gzip "$TmpBackupDir/$FileBackupName.tar"
log "Done backing up OS Files"


## Backup the MySQL databases
if [ "$EnableDBBackups" = true ]; then
	log 'Beginning to backup DB Files'
	tar -cf "$TmpBackupDir/$DBBackupName.tar" --files-from /dev/null
	for db in "${DBsToBackup[@]}"
	do
			filename="$db.sql"
			log "Dumping DB $db to $TmpBackupDir/$filename"
			mysqldump --defaults-extra-file=$MySQLConfig $db > "$TmpBackupDir/$filename"
			log "Backing up DB $db to $TmpBackupDir/$DBBackupName.tar.gz"
			tar -pPrf "$TmpBackupDir/$DBBackupName.tar" "$TmpBackupDir/$filename"
			log "Deleting uncompressed sql backup for DB $db"
			rm "$TmpBackupDir/$filename"
	done
	gzip "$TmpBackupDir/$DBBackupName.tar"
else
	log "Skipping backup of DB files, since config is set to false"
fi
log "Done backing up DB files"


## Sending new files to S3
log 'Syncing backups to S3'
s3cmd put --config=$S3ConfigFile --recursive $TmpBackupDir/* $S3URI
if [ $? -ne 0 ]; then
    error  "S3 Sync Failed for $TmpBackupDir on S3 Bucket $S3URI"
		sendMail "S3 Sync Failed" "S3 Sync failed for $TmpBackupDir on S3 Bucket $S3URI"
		error "S3 Backup failed, leaving local files in place at $TmpBackupDir"
    exit
fi
log "S3 Sync is complete"
log "deleting local backups"
rm -rf $TmpBackupDir/*

log 'All Done! Yay! (",)'

## Email Report of What Exists on S3 in Today's Folder
s3cmd ls -r --config=$S3ConfigFile $S3URI > "${LogDir}/s3report.txt"
sendMail "Backup Finished" "Backup Finished, s3 bucket contents attached" "$(base64 -w 0 ${logDir}/s3report.txt)"
