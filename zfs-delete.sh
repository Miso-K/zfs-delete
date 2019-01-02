#!/usr/bin/env bash

usage="$(basename "$0") -s SECONDS -m MINUTES -h HOURS -d DAYS -p GREP_PATTERN [-t] [-g]\n
arguments:\n
    -s delete snapshots older than SECONDS\n
    -m delete snapshots older than MINUTES\n
    -h delete snapshots older than HOURS\n
    -d delete snapshots older than DAYS\n
    -p the grep pattern to use\n
    -t test run, do not destroy the snapshots just print them\n
    -g group of dataset in pattern\
    -e the grep pattern to excluse (use with -g)
"

while getopts ":tgs:m:h:d:p:e:" opt; do
  case $opt in
    s)
      seconds=$OPTARG
      ;;
    m)
      minutes=$OPTARG
      ;;
    h)
      hours=$OPTARG
      ;;
    d)
      days=$OPTARG
      ;;
    p)
      pattern=$OPTARG
      ;;
    t)
      test_run=true
      ;;
    g)
      group=true
      ;;
    e)
      excluded=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" 1>&2
      echo -e $usage 1>&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." 1>&2
      echo -e $usage 1>&2
      exit 1
      ;;
  esac
done

if [[ -z $pattern ]]; then
  echo -e "No grep pattern supplied\n" 1>&2
  echo -e $usage 1>&2
  exit 1
fi

if [[ -z $days ]]; then
  days=0
fi

if [[ -z $hours ]]; then
  hours=0
fi

if [[ -z $minutes ]]; then
  minutes=0
fi

if [[ -z $seconds ]]; then
  seconds=0
fi

# Figure out which platform we are running on, more specifically, whic version of date
# we are using. GNU date behaves different thant date on OSX and FreeBSD
platform='unknown'
unamestr=$(uname)

if [[ "$unamestr" == 'Linux' ]]; then
  platform='linux'
elif [[ "$unamestr" == 'FreeBSD' ]]; then
  platform='bsd'
elif [[ "$unamestr" == 'OpenBSD' ]]; then
  platform='bsd'
elif [[ "$unamestr" == 'Darwin' ]]; then
  platform='bsd'
else
  echo -e "unknown platform $unamestr 1>&2"
  exit 1
fi

ZFS="/sbin/zfs"

compare_seconds=$(($days * 24 * 60 * 60 + $hours * 60 * 60 + $minutes * 60 + $seconds))
if [ $compare_seconds -lt 1 ]; then
  echo -e time has to be in the past 1>&2
  echo -e $usage 1>&2
  exit 1
fi

if [[ "$platform" == 'linux' ]]; then
compare_timestamp=`date --date="-$(echo $compare_seconds) seconds" +"%s"`
else
compare_timestamp=`date -j -v-$(echo $compare_seconds)S +"%s"`
fi

# for in uses \n as a delimiter
do_delete() {

    eval SNAPSHOTS="$1"
    #COMPARE_TIMESTAMP=$2

    compare_seconds=$(($days * 24 * 60 * 60 + $hours * 60 * 60 + $minutes * 60 + $seconds))
    if [ $compare_seconds -lt 1 ]; then
      echo -e time has to be in the past 1>&2
      echo -e $usage 1>&2
      exit 1
    fi

    if [[ "$platform" == 'linux' ]]; then
      compare_timestamp=`date --date="-$(echo $compare_seconds) seconds" +"%s"`
    else
      compare_timestamp=`date -j -v-$(echo $compare_seconds)S +"%s"`
    fi


    old_ifs=$IFS
    IFS=$'\n'

    for line in $SNAPSHOTS; do
      snapshot=`echo $line | cut -f 1`
      creation_date=`echo $line | cut -f 2`

      if [[ "$platform" == 'linux' ]]; then
        creation_date_timestamp=`date --date="$creation_date" "+%s"`
      else
        creation_date_timestamp=`date -j -f "%a %b %d %H:%M %Y" "$creation_date" "+%s"`
      fi

      # Check if the creation date of a snapshot is less than our compare date
      # Meaning if it is older than our compare date
      # It is younger, we can stop processing since we the list is sorted by
      # compare date '-s creation'
      if [ $creation_date_timestamp -lt $compare_timestamp ]
      then
        if [[ -z $test_run ]]; then
          echo "DELETE: $snapshot from $creation_date"
          $ZFS destroy $snapshot
        else
          echo "WOULD DELETE: $snapshot from $creation_date"
        fi
      else
        echo "KEEP: $snapshot from $creation_date"
        echo "No more snapshots to be processed for $pattern. Skipping.."
        #continue
        break
      fi
    done
    IFS=$old_ifs
}

# get a list of snapshots sorted by creation date, so that we get the oldest first
# This will allow us to skip the loop early

if [[ -z $group ]]; then
  snapshots=`$ZFS list -H -t snapshot -o name,creation -s creation | grep $pattern`
  if [[ -z $snapshots ]]; then
    echo "no snapshots found for pattern $pattern"
    exit 0
  else
    do_delete "\${snapshots}"
  fi

else

  # delete dataset snapshots
  snapshots=`$ZFS list -H -t snapshot -o name,creation -s creation | grep "$pattern@"`
  if [[ -z $snapshots ]]; then
    echo "no snapshots found for pattern $pattern"
  else
    do_delete "\${snapshots}"
  fi

  # delete child snapshots
  # zfs list -o name | grep "pattern" | grep -vE "$excluded" for exlude

  if [[ -z $excluded ]]; then
    zlist=$($ZFS list -o name | grep "$pattern/")
  else
    zlist=$($ZFS list -o name | grep "$pattern/" | grep -vE "$excluded")
  fi

  while read line
  do
      snapshots=`$ZFS list -H -t snapshot -o name,creation -s creation | grep $line`
      if [[ -z $snapshots ]]; then
        echo "no snapshots found for pattern $pattern"
        continue
      else
        do_delete "\${snapshots}"
      fi
  done <<< "$zlist"
fi

exit 0
