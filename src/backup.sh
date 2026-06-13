#!/bin/sh
set -e

if [ "$1" = "cron" ]; then
    # Default to every 6 hours if CRON_SCHEDULE isn't provided
    SCHEDULE=${CRON_SCHEDULE:-"0 */6 * * *"}
    echo "Initializing automated backup scheduler..."
    echo "Cron schedule set to: $SCHEDULE"
    
    echo "$SCHEDULE /backup.sh run >> /proc/1/fd/1 2>&1" > /etc/crontabs/root
    
    exec crond -f -d 8
fi

if [ "$1" = "run" ]; then
    echo "========================================================="
    echo "STARTING MONGODB BACKUP: $(date)"
    echo "========================================================="
    
    : "${MONGO_URI:?Missing MONGO_URI environment variable}"
    : "${AZURE_ACCOUNT_NAME:?Missing AZURE_ACCOUNT_NAME environment variable}"
    : "${AZURE_CONTAINER:?Missing AZURE_CONTAINER environment variable}"
    : "${AZURE_SAS_TOKEN:?Missing AZURE_SAS_TOKEN environment variable}"

    CLEAN_SAS=$(echo "$AZURE_SAS_TOKEN" | sed 's/^?//')
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="mongo_backup_${TIMESTAMP}.archive.gz"
    LOCAL_PATH="/tmp/${BACKUP_FILE}"

    echo "Creating compressed database archive..."
    if mongodump --uri="${MONGO_URI}" --archive="${LOCAL_PATH}" --gzip; then
        echo "Database dump created successfully."
    else
        echo "ERROR: mongodump failed!"
        exit 1
    fi

    AZURE_URL="https://${AZURE_ACCOUNT_NAME}.blob.core.windows.net/${AZURE_CONTAINER}/${BACKUP_FILE}?${CLEAN_SAS}"
    echo "Uploading archive to Azure Blob Storage..."
    
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o /dev/null -X PUT -T "${LOCAL_PATH}" \
         -H "x-ms-blob-type: BlockBlob" \
         -H "x-ms-version: 2023-11-03" \
         "${AZURE_URL}")

    if [ "$HTTP_STATUS" -eq 201 ]; then
        echo "SUCCESS: Upload completed perfectly."
    else
        echo "ERROR: Azure upload failed with HTTP status code: $HTTP_STATUS"
        rm -f "${LOCAL_PATH}"
        exit 1
    fi

    echo "Cleaning up local workspace..."
    rm -f "${LOCAL_PATH}"
    echo "Backup sequence finished successfully."
fi
