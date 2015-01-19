# Introduction
this is a simple shell script which will tar up folders/files at the os level, and tar a dump of a mysql database and upload it to amazon s3 using s3cmd.

## s3cmd - Installation
Download the zip of s3cmd to /opt, and install it.

```shell
wget -O- -q http://s3tools.org/repo/deb-all/stable/s3tools.key | sudo apt-key add -;
sudo wget http://s3tools.org/repo/deb-all/stable/s3tools.list -O /etc/apt/sources.list.d/s3tools.list;
sudo apt-get update && sudo apt-get install s3cmd python-dateutil unzip -y;
sudo useradd s3backups -m -s /usr/sbin/nologin;
```
## Backup script - Installation
The shell script needs to be cloned or copied into `/opt/` and `chown` to `root:root`.

```shell
sudo -i /bin/zsh; #login as root
git clone https://git.relative.media/mhdevita/s3-backup-script.git /opt/backup
chown -R s3backups:s3backups /opt/backup && chmod -R 750 /opt/backup && chmod g+s /opt/backup;

#fix the permissions
chown -R s3backups:s3backups /opt/backup && chmod -R 750 /opt/backup;
```

## s3cmd - Configuration
The command `s3cmd --configure` will create the `.s3cfg` file we need, but it needs to go in root's homedir and not ours. 
You can either run the command and move the config file. Or `sudo -i /bin/bash` to run bash as root and then run it.

```shell
#login as root.
sudo -i /bin/zsh
s3cmd --configure; mv -f ~/.s3cfg /opt/backup/.s3cfg && chown s3backups:s3backups /opt/backup/.s3cfg && chmod 750 /opt/backup/.s3cfg;
#to test stuff works either sudo -u as s3backups or as root..
sudo -u s3backups s3cmd ls s3://<bucket> -c /opt/backup/.s3cfg;
#should list out bucket contents.
```

### Create a mysql backup user with read privileges only.
login to mysql cli as root and run the following sql statements, replace the PASSWORD with a real one.

```sql
CREATE USER 'backup'@'localhost' IDENTIFIED BY 'SOMEPASSWORD';
GRANT LOCK TABLES, SELECT ON *.* TO 'backup'@'localhost';
FLUSH PRIVILEGES;
```

## Backup Script Configuration

```shell
sudo mv database.sample.cnf database.cnf;
sudo mv backup.sample.cfg backup.cfg;
```

edit `database.cnf` with this new user/password, and the hostname if mysql isn't on the same host.


edit `backup.cfg` and fill in the following info..

* **SENDTOEMAIL:** Email address to send backup alerts to
* **MANDRILLKEY:** API Key from Mandrill for Emails
* **FROMEMAIL:** Who are we sending this from?
* **FROMNAME:** Who are we sending this from as a name
* **S3URI:** the `s3://<bucketname>/backups/` to upload to (make sure there is a trailing slash)
* **s3ConfigFile:** path to the config file, should be /opt/backup/.s3cfg by default
* **filesToBackup:** array of files or folders to backup (no trailing slash)
* **DBsToBackup:** array of database names to backup (make sure your backup user has privileges to these DBs)
* **TmpBackupDir:** path to where the backup files will be stored temporarily while the script runs
* **MySQLConfig:** path to the database.cnf file that has the backup credentials

you can test this script by running `sudo -u s3backups /opt/backup/backup.sh;`. It should upload to s3 and shoot you an email.