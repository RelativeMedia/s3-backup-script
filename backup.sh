#!/bin/bash
source backup.cfg
sendMail(){
	msg='{ "async": false, "key": "'$MANDRILLKEY'", "message": { "from_email": "'$FROMEMAIL'", "from_name": "'$FROMNAME'", "return_path_domain": null, "subject": "['$HOSTNAME'] '$1'", "text": "Backups Complete For '$HOSTNAME'.", "attachments": [{ "type": "text/plain", "name": "backup_report.txt", "content": "'$2'" }], "to": [{ "email": "'$SENDTOEMAIL'", "type": "to" }] }}';
    results=$(curl -A 'Mandrill-Curl/1.0' -d "$msg" 'https://mandrillapp.com/api/1.0/messages/send.json' -s 2>&1);
    echo "$results" | grep "sent" -q;
    if [ $? -ne 0 ]; then
        echo "An error occured: $results";
    fi
    #/usr/bin/mail -s "[$HOSTNAME] $1" "$SENDTOEMAIL" < $2
}


## Check we can write to the backups directory
if [ ! -d "$TmpBackupDir" ]
then
    mkdir -p $TmpBackupDir
else
    if [ -w "$TmpBackupDir" ]
    then
        # Do nothing and move along.
        echo 'Found and is writable:  '$TmpBackupDir
    else
        echo "Can't write to: "$TmpBackupDir
        sendMail "Backup Error" "Can't write to: $TmpBackupDir"
        exit
    fi
fi

echo ''
tar -cf "$TmpBackupDir/$FileBackupName.tar" --files-from /dev/null
for item  in "${filesToBackup[@]}"
do
    echo "Backing up $item to $TmpBackupDir/$FileBackupName.tar.gz"
    tar -pPrf "$TmpBackupDir/$FileBackupName.tar" "$item"
done
gzip "$TmpBackupDir/$FileBackupName.tar"

## Backup the MySQL databases
echo ''
tar -cf "$TmpBackupDir/$DBBackupName.tar" --files-from /dev/null
for db in "${DBsToBackup[@]}"
do
    filename="$db.sql"
    echo "Dumping DB $db to $TmpBackupDir/$filename"
    mysqldump --defaults-extra-file=$MySQLConfig $db > "$TmpBackupDir/$filename"
    echo "Backing up DB $db to $TmpBackupDir/$DBBackupName.tar.gz"
    tar -pPrf "$TmpBackupDir/$DBBackupName.tar" "$TmpBackupDir/$filename"
    echo "Deleting uncompressed sql backup for DB $db"
    rm "$TmpBackupDir/$filename"
done
gzip "$TmpBackupDir/$DBBackupName.tar"

## Sending new files to S3
echo ''
echo 'Syncing backups to S3'
s3cmd put --config=$S3ConfigFile --recursive $TmpBackupDir/* $S3URI
if [ $? -ne 0 ]; then
    sendMail "S3 Sync Failed" "S3 Sync failed for $TmpBackupDir on S3 Bucket $S3URI"
    exit
fi

echo ''
echo "deleting local backups now that sync is complete"
rm -rf $TmpBackupDir/*

echo 'All Done! Yay! (",)'

## Email Report of What Exists on S3 in Today's Folder
s3cmd ls -r --config=$S3ConfigFile $S3URI > "logs/s3report.txt"
sendMail "Backup Finished" "$(base64 -w 0 logs/s3report.txt)"
