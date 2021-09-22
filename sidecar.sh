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
        OBJECT_ID=$( echo $i | jq -r .object_id )
        touch "/data/${BASE_URL}/${FILE_NAME}_PLACEHOLDER.txt"
        echo "THIS IS JUST A PLACEHOLDER FILE TO VISUALIZE THE FILES!\n" >> "/data/${BASE_URL}/${FILE_NAME}_PLACEHOLDER.txt"
        echo "Please run \"gen3 --endpoint ${BASE_URL} pull_object ${OBJECT_ID}\" from Terminal to download this data file using Gen3 CLI.\n" >> "/data/${BASE_URL}/${FILE_NAME}_PLACEHOLDER.txt"
        echo "Or check the tutorial notebook to learn how to download a single or multiple data files at once using Gen3 SDK\n" >> "/data/${BASE_URL}/${FILE_NAME}_PLACEHOLDER.txt"
    done
    log "Finished populating placeholder files"
}

function apikeyfile() {
    if [[ ! -d "/gen3" ]]; then
        log "Please mount shared docker volume under /gen3. Gen3 SDK will not be configured correctly.."
        mkdir /gen3
    fi
    if [[ -z $GEN3_API_KEY ]]; then
        log '$GEN3_API_KEY not set. Skipping writing api key to file. WARNING: Gen3 SDK will not be configured correctly.'
        exit 5
    else
        log "Writing apiKey to ~/.gen3/credentials.json"
        apikey=$(jq --arg key0   'api_key' \
            --arg value0 "${GEN3_API_KEY}" \
            '. | .[$key0]=$value0 '  \
            <<<'{}')
        echo "$apikey" > /gen3/credentials.json
    fi
}

function get_access_token() {
    log "Getting access token using mounted API key from $BASE_URL/user/"
    export ACCESS_TOKEN=$(curl -H "Content-Type: application/json" -X POST "https://$BASE_URL/user/credentials/api/access_token/" -d "{ "api_key": "${GEN3_API_KEY}" }" 2>/dev/null | jq -c .manifests[0])
}

function main() {
    if [[ -z "${BASE_URL}" ]]; then
        echo "No base url set"
        exit 1
    fi

    # Gen3SDK should work if $GEN3_API_KEY is set
    apikeyfile
    get_access_token

    if [[ -z "${ACCESS_TOKEN}" ]]; then
        echo "No access token set"
        exit 2
    fi

    if [[ ! -d "/data/${BASE_URL}" ]]; then
        log "Creating /data/$BASE_URL/ directory"
        mkdir "/data/${BASE_URL}/"
    fi
    log "Trying to populate data from MDS..."


    populate

}


main
