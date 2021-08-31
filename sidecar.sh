function log(){
    LOGFILE="/data/populate_log.txt"
    if [[ ! -f ${LOGFILE} ]]; then 
        touch ${LOGFILE}
    fi
    TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
    echo "${TIMESTAMP}: $1"
    echo "${TIMESTAMP}: $1" >> ${LOGFILE}
}


function populate() {
    PLACEHOLDER_MESSAGE=$(cat <<EOL
THIS IS JUST A PLACEHOLDER FILE TO VISUALIZE THE FILES! 

PLEASE RUN "gen3 download XXXXX" FROM A NOTEBOOK TO DOWNLOAD THE ACTUAL DATA FILE. 

FOR MORE INFORMATION ON HOW TO DOWNLOAD FILES, CHECK THE TUTORIAL NOTEBOOK.    
EOL
)

    log "querying manifest service at $BASE_URL/manifests/"
    MANIFESTS=$(curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$BASE_URL/manifests/" 2>/dev/null | jq -c .manifests[0])
    log "Manifests: $MANIFESTS"
    while [ -z "$MANIFESTS" ]; do
        log "Unable to get manifests from '$BASE_URL/manifests/'"
        log $MANIFESTS
        log "sleeping for 15 seconds before trying again.."
        sleep 15
        MANIFESTS=$(curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$BASE_URL/manifests/" 2>/dev/null | jq -c .manifests[0])
    done
    FILENAME=$(echo "${MANIFESTS}" | jq -r .filename)
    MANIFEST=$(curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$BASE_URL/manifests/file/$FILENAME" 2>/dev/null | jq -r .)
    echo "${MANIFEST}" > /data/manifest.json
    log "Populating placefolder files..."
    jq -c '.[]' /data/manifest.json | while read i; do
        # C_URL=$( echo $i | jq -r .commons_url )
        FILE_NAME=$( echo $i | jq -r .file_name )
        echo "${PLACEHOLDER_MESSAGE}" | tee "/data/${BASE_URL}/${FILE_NAME}_PLACEHOLDER.txt" >/dev/null
    done
    log "Finished populating placeholder files"
}

function main() {
    if [[ -z "${BASE_URL}" ]]; then
        echo "No base url set"
        exit 1
    elif [[ -z "${ACCESS_TOKEN}" ]]; then 
        echo "No access token set"
        exit 2
    fi
    if [[ ! -f "/data/${BASE_URL}" ]]; then 
        mkdir "/data/${BASE_URL}/"
    fi
    log "Trying to populate data from MDS..."
    
    populate

}


main