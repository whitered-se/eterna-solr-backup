#!/bin/bash

function print_usage {
    echo "usage: $0 [-s solr host] [-u username] [-p password] [-l location]"
}

function solr_api_request {
    curl_args=('-s')
    [[ -n "${SOLR_USERNAME}" ]] && curl_args+=('-u' "$SOLR_USERNAME:$SOLR_PASSWORD")

    while test $# != 0; do
        case "$1" in
        -s)
            curl_args+=('-o' '/dev/null')
            ;;
        *)
            curl_args+=("$1")
            ;;
        esac
        shift
    done

    curl "${curl_args[@]}"
}

while test $# != 0; do
    case "$1" in
    -s)
        SOLR_HOST=$2
        shift
        ;;
    -u)
        SOLR_USERNAME=$2
        shift
        ;;
    -p)
        SOLR_PASSWORD=$2
        shift
        ;;
    -l)
        SOLR_BACKUP_LOCATION=$2
        shift
        ;;
    -h)
        print_usage
        exit
        ;;
    *)
        echo "$0: invalid option: $1"
        print_usage
        exit 1
        ;;
    esac
    shift
done

if [[ -z "${SOLR_HOST}" ]]; then
    echo "SOLR host not defined! Specify a SOLR host with option '-s <solr host>' or environment variable SOLR_HOST. E.g. \"http://localhost:8983\"."
fi

if [[ -z "${SOLR_BACKUP_LOCATION}" ]]; then
    echo "SOLR backup location not defined! Specify a backup location with option '-l <location>' or environment variable SOLR_BACKUP_LOCATION. E.g. \"/path/to/my/shared/drive\"."
fi

if [[ -z "${SOLR_HOST}" ]] || [[ -z "${SOLR_BACKUP_LOCATION}" ]]; then
    echo "Exiting."
    exit 1
fi

collections=(
    "RepresentationInformation"
    "TransferredResource"
    "DisposalConfirmation"
    "PreservationAgent"
    "PreservationEvent"
    "RiskIncidence"
    "File"
    "DIPFile"
    "DIP"
    "Representation"
    "Risk"
    "AIP"
    "JobReport"
    "Job"
    "Members"
    "Notification"
    "ActionLog"
)

collections_count=${#collections[@]}

backup_running=$()
backup_status=$()

for ((i = 0; i < collections_count; i++)); do
     mkdir -p "${SOLR_BACKUP_LOCATION}/${collections[$i]}"
done

echo -n "Clearing request statuses..."
for ((i = 0, id = 1000; i < collections_count; i++, id++)); do
    url="${SOLR_HOST}/solr/admin/collections?action=DELETESTATUS&requestid=${id}"
    solr_api_request -s "$url"
done
echo " Done!"

echo -n "Clearing snapshots..."
for ((i = 0; i < collections_count; i++)); do
    url="${SOLR_HOST}/solr/admin/collections?action=DELETESNAPSHOT&collection=${collections[$i]}&commitName=${collections[$i]}_backup&followAliases=true"
    solr_api_request -s "$url"
done
echo " Done!"

echo -n "Creating snapshots..."
for ((i = 0; i < collections_count; i++)); do
    url="${SOLR_HOST}/solr/admin/collections?action=CREATESNAPSHOT&collection=${collections[$i]}&commitName=${collections[$i]}_backup&followAliases=true"
    solr_api_request -s "$url"
done
echo " Done!"

echo -n "Starting backups..."
for ((i = 0, id = 1000; i < collections_count; i++, id++)); do
    url="${SOLR_HOST}/solr/admin/collections?action=BACKUP&collection=${collections[$i]}&name=${collections[$i]}&location=file://${SOLR_BACKUP_LOCATION}&async=${id}"
    if [[ -n "${SOLR_MAX_NUM_BACKUP_POINTS}" ]]; then
        url="${url}&maxNumBackupPoints=${SOLR_MAX_NUM_BACKUP_POINTS}"
    fi
    solr_api_request -s "$url"
    backup_running[i]=true
done
echo " Done!"

echo -n "Waiting for backups to complete..."
while true; do
    sleep 10
    running=false

    for ((i = 0, id = 1000; i < collections_count; i++, id++)); do
        if [[ ${backup_running[$i]} = false ]]; then
            continue
        fi

        url="${SOLR_HOST}/solr/admin/collections?action=REQUESTSTATUS&requestid=${id}"
        status=$(solr_api_request "$url")
        state=$(echo -n "$status" | jq -r '.status.state')

        if [[ $state = "running" ]]; then
            running=true
        else
            backup_running[i]=false
            backup_status[i]="$status"
        fi
    done

    [[ $running = true ]] || break
done
echo " Done!"

echo "Backup statuses:"
for ((i = 0; i < collections_count; i++)); do
    echo "${backup_status[$i]}" | jq 'with_entries(select(.key=="collection", .key=="response", .key=="deleted", .key=="status"))'
done;

echo -n "Deleting request statuses..."
for ((i = 0, id = 1000; i < collections_count; i++, id++)); do
    url="${SOLR_HOST}/solr/admin/collections?action=DELETESTATUS&requestid=${id}"
    solr_api_request -s "$url"
done
echo " Done!"

echo -n "Deleting snapshots..."
for ((i = 0; i < collections_count; i++)); do
    url="${SOLR_HOST}/solr/admin/collections?action=DELETESNAPSHOT&collection=${collections[$i]}&commitName=${collections[$i]}_backup&followAliases=true"
    solr_api_request -s "$url"
done
echo -e " Done!\n"
