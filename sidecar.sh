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

function apikeyfile() {
    if [[ ! -d "/gen3" ]]; then
        log "Please mount shared docker volume under /gen3. Gen3 SDK will not be configured correctly.."
        mkdir /gen3
    fi
    if [[ -z $API_KEY || -z $API_KEY_ID ]]; then
        log '$API_KEY or $API_KEY_ID not set. Skipping writing api key to file. WARNING: Gen3 SDK will not be configured correctly.'
        exit 5
    else 
        log "Writing apiKey to ~/.gen3/credentials.json"
        apikey=$(jq --arg key0   'api_key' \
            --arg value0 "${API_KEY}" \
            --arg key1   'key_id' \
            --arg value1 "${API_KEY_ID}" \
            '. | .[$key0]=$value0 | .[$key1]=$value1'  \
            <<<'{}')
        echo "$apikey" > /gen3/credentials.json
    fi
}

function main() {
    if [[ -z "${BASE_URL}" ]]; then
        echo "No base url set"
        exit 1
    elif [[ -z "${ACCESS_TOKEN}" ]]; then 
        echo "No access token set"
        exit 2
    fi
    if [[ ! -d "/data/${BASE_URL}" ]]; then 
        log "Creating /data/$BASE_URL/ directory"
        mkdir "/data/${BASE_URL}/"
    fi
    log "Trying to populate data from MDS..."
    
    apikeyfile
    populate

}


main