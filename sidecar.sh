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
    log "querying manifest service at $GEN3_ENDPOINT/manifests/"
    MANIFESTS=$(curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/" 2>/dev/null | jq -c ".manifests | .[-1]")
    while [ -z "$MANIFESTS" ]; do
        log "Unable to get manifests from '$GEN3_ENDPOINT/manifests/'"
        log $MANIFESTS
        log "sleeping for 15 seconds before trying again.."
        sleep 15
        MANIFESTS=$(curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/" 2>/dev/null | jq -c ".manifests | .[-1]")
    done
    FILENAME=$(echo "${MANIFESTS}" | jq -r .filename)
    MANIFEST=$(curl -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/file/$FILENAME" 2>/dev/null | jq -r .)
    echo "${MANIFEST}" > /data/manifest.json
    log "Populating placefolder files..."
    jq -c '.[]' /data/manifest.json | while read i; do
        # C_URL=$( echo $i | jq -r .commons_url )
        FILE_NAME=$( echo $i | jq -r .file_name )
        OBJECT_ID=$( echo $i | jq -r .object_id )
        # only care if there is an object ID
        if [[ -n "${OBJECT_ID}" ]]; then
            if [[ -n "${FILE_NAME}" ]]; then
                # if file name exist, use it
                touch "/data/${GEN3_ENDPOINT}/${FILE_NAME}_PLACEHOLDER.txt"
                echo -en "THIS IS JUST A PLACEHOLDER FILE TO VISUALIZE THE FILES! \n\n" >> "/data/${GEN3_ENDPOINT}/${FILE_NAME}_PLACEHOLDER.txt"
                echo -en "Please run \"gen3 pull_object ${OBJECT_ID}\" from Terminal to download this data file using Gen3 CLI. \n\n" >> "/data/${GEN3_ENDPOINT}/${FILE_NAME}_PLACEHOLDER.txt"
                echo -en "Or check the tutorial notebook to learn how to download a single or multiple data files at once using Gen3 SDK \n\n" >> "/data/${GEN3_ENDPOINT}/${FILE_NAME}_PLACEHOLDER.txt"
            else
                # otherwise, name it using object ID
                touch "/data/${GEN3_ENDPOINT}/${OBJECT_ID}_PLACEHOLDER.txt"
                echo "THIS IS JUST A PLACEHOLDER FILE TO VISUALIZE THE FILES! \n\n" >> "/data/${GEN3_ENDPOINT}/${OBJECT_ID}_PLACEHOLDER.txt"
                echo "Please run \"gen3 pull_object ${OBJECT_ID}\" from Terminal to download this data file using Gen3 CLI. \n\n" >> "/data/${GEN3_ENDPOINT}/${OBJECT_ID}_PLACEHOLDER.txt"
                echo "Or check the tutorial notebook to learn how to download a single or multiple data files at once using Gen3 SDK \n\n" >> "/data/${GEN3_ENDPOINT}/${OBJECT_ID}_PLACEHOLDER.txt"
            fi
        else
            log "No object ID found for manifest entry, skipping..."
        fi
    done
    log "Finished populating placeholder files"
    while true; do
        # Sleeping forever so EKS will be happy
        sleep 10000
    done
}

function apikeyfile() {
    if [[ ! -d "/.gen3" ]]; then
        log "Please mount shared docker volume under /.gen3. Gen3 SDK will not be configured correctly.."
        mkdir /.gen3
    fi
    if [[ -z $API_KEY ]]; then
        log '$API_KEY not set. Skipping writing api key to file. WARNING: Gen3 SDK will not be configured correctly.'
        exit 5
    else
        log "Writing apiKey to ~/.gen3/credentials.json"
        apikey=$(jq --arg key0   'api_key' \
            --arg value0 "${API_KEY}" \
            '. | .[$key0]=$value0 '  \
            <<<'{}')
        echo "$apikey" > /.gen3/credentials.json
    fi
}

function get_access_token() {
    log "Getting access token using mounted API key from https://$GEN3_ENDPOINT/user/"
    export ACCESS_TOKEN=$(curl -H "Content-Type: application/json" -X POST "https://$GEN3_ENDPOINT/user/credentials/api/access_token/" -d "{ \"api_key\": \"${API_KEY}\" }" 2>/dev/null | jq -r .access_token)
}

function main() {
    if [[ -z "${GEN3_ENDPOINT}" ]]; then
        log "No base url set"
        exit 1
    fi

    # Gen3SDK should work if $API_KEY is set
    apikeyfile
    get_access_token

    if [[ -z "${ACCESS_TOKEN}" ]]; then
        log "No access token set"
        exit 2
    fi

    if [[ ! -d "/data/${GEN3_ENDPOINT}" ]]; then
        log "Creating /data/$GEN3_ENDPOINT/ directory"
        mkdir "/data/${GEN3_ENDPOINT}/"
    fi
    log "Trying to populate data from MDS..."
    populate
}


main
