#!/bin/bash

## Email Variables
EMAILDATE=`date --date="today" +%y-%m-%d`
SENDTOEMAIL="your@emailaddress.com"

### The URI of the S3 bucket.
### This is usually in the form of domain.com for me 
S3URI='s3://s3bucket/backups/'
S3ConfigFile='/opt/backup/.s3cfg'

### An array of directories you want to backup (I included a few configuration directories to).
### Assuming standard ubuntu with apache2, and mysql
filesToBackup=(
'/var/www'
'/etc/passwd'
'/etc/hosts'
'/etc/fstab'
'/etc/group'
'/etc/apache2'
'/etc/mysql'
)

### The databases you want to backup
DBsToBackup=(
'yourdbname'
)
### The directory we're going to story our backups in on this server.
### dont use a trailing slash.
TmpBackupDir='/opt/backup/temp'
### The MySQL details
MySQLConfig='/opt/backup/database.cnf'

today=`date --date="today" +%m%d%y`
FileBackupName="os.$today"
DBBackupName="db.$today"

sendMail(){
  /usr/bin/mail -s "[$HOSTNAME] $1" "$SENDTOEMAIL" < $2
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
s3cmd ls -r --config=$S3ConfigFile $S3URI > "/tmp/s3report.txt"
EMAILMESSAGE="/tmp/s3report.txt"
sendMail "Backup Finished" "$EMAILMESSAGE"
