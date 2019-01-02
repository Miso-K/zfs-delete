This script working well with https://github.com/Miso-K/zfs-backup.

The main purpose of this script is to remove old zfs snapshots based on input parameters.
It is working well with cron to automate process of removing old snapshots.

./zfs-delete.sh -s SECONDS -m MINUTES -h HOURS -d DAYS -p GREP_PATTERN -t (test run) -g (group) -e (excluded)

EXAMPLES:

Delete snapshots containg string pool1
./zfs-delete.sh -d 11 -t -p pool1

Delete snapshots from pool1/ds1 older then 10 days:
./zfs-delete.sh -d 10 -t -p "pool1/ds1"

Delete snapshots from pool1 and exclude ds2 and ds3:
./zfs-delete.sh -d 14 -t -p "pool1" -g -e "ds2|ds3"
