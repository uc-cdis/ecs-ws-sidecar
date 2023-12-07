function log(){
    LOGFILE="/data/populate_log.txt"
    if [[ ! -f ${LOGFILE} ]]; then
        touch ${LOGFILE}
    fi
    TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
    echo "${TIMESTAMP}: $1"
    echo "${TIMESTAMP}: $1" >> ${LOGFILE}
}


populate_notebook() {
    MANIFEST=$1
    shift
    FOLDER=$1
    shift
    manifest_pull="!gen3  drs-pull manifest manifest.json"
    manifest_ls="!gen3 drs-pull ls manifest.json"
    jq --arg cmd "$manifest_ls" '.cells[1].source |= $cmd' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp" && mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"
    jq --arg cmd "$manifest_pull" '.cells[3].source |= $cmd' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp" && mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"
    echo $MANIFEST | jq -c '.[]' | while read j; do
        obj=$(echo $j | jq -r .object_id)
        filename=$(echo $j | jq -r .file_name)
        filesize=$(echo $j | jq -r .file_size)

        # Need to add a literal newline character that's why the quote is ending on next line
        drs_pull="!gen3 drs-pull object $obj

"
        # Need to add a literal newline character that's why the quote is ending on next line
        jq --arg cmd "# File name: $filename - File size: $filesize
" '.cells[5].source += [$cmd]' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp"
        mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"

        jq --arg cmd "$drs_pull" '.cells[5].source += [$cmd]' "$FOLDER/data.ipynb" > "$FOLDER/data.tmp"
        mv "$FOLDER/data.tmp" "$FOLDER/data.ipynb"


    done
    log "Done populating notebook"
}

function populate() {
    log "querying manifest service at $GEN3_ENDPOINT/manifests/"
    MANIFESTS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/")
    while [ -z "$MANIFESTS" ]; do
        log "Unable to get manifests from '$GEN3_ENDPOINT/manifests/'"
        log $MANIFESTS
        log "sleeping for 15 seconds before trying again.."
        sleep 15
        MANIFESTS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/")
    done


    #  Loop over each exported manifest
    echo $MANIFESTS | jq -c '.manifests[]' | while read i; do
        FILENAME=$(echo "${i}" | jq -r .filename)
        FOLDERNAME=$(echo "${FILENAME%.*}")
        FOLDER="/data/${GEN3_ENDPOINT}/exported-${FOLDERNAME}"

        if [ ! -d "$FOLDER" ]; then
            log "mkdir -p $FOLDER"
            mkdir -p $FOLDER

            # make sure folder can be written to by notebook
            chown -R 1000:100 $FOLDER
            MANIFEST=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/file/$FILENAME")
            echo "${MANIFEST}" > $FOLDER/manifest.json

            log "Creating notebook for $FILENAME"
            cp ./template_manifest.json $FOLDER/data.ipynb
            populate_notebook "$MANIFEST" "$FOLDER"
        fi
    done

    # Make sure notebook user has write access to the folders
    chown -R 1000:100 /data
}

function apikeyfile() {
    if [[ ! -d "/.gen3" ]]; then
        log "Please mount shared docker volume under /.gen3. Gen3 SDK will not be configured correctly.."
        mkdir /.gen3
    fi
    if [[ -z $API_KEY ]]; then
        log '$API_KEY not set. Skipping writing api key to file. WARNING: Gen3 SDK will not be configured correctly.'
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
    ACCESS_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST "https://$GEN3_ENDPOINT/user/credentials/api/access_token/" -d "{ \"api_key\": \"${API_KEY}\" }" | jq -r .access_token)
    while [ -z "$ACCESS_TOKEN" ]; do
        log "Unable to get ACCESS TOKEN using API key."
        log "sleeping for 15 seconds before trying again.."
        sleep 15
        ACCESS_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST "https://$GEN3_ENDPOINT/user/credentials/api/access_token/" -d "{ \"api_key\": \"${API_KEY}\" }" | jq -r .access_token)
    done
    export ACCESS_TOKEN="$ACCESS_TOKEN"
}

function mount_hatchery_files() {
    log "Mounting Hatchery files"
    FOLDER="/data"
    if [ ! -d "$FOLDER" ]; then
        mkdir $FOLDER
    fi

    echo "Fetching files to mount..."
    DATA=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/lw-workspace/mount-files")
    echo $DATA | jq -c -r '.[]' | while read file_path; do
        echo "Mounting '$file_path'"
        mkdir -p "$FOLDER/$(dirname "$file_path")"
        curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/lw-workspace/mount-files?id=$file_path" > $FOLDER/$file_path
    done

    # Make sure notebook user has write access to the folders
    chown -R 1000:100 $FOLDER
}

function main() {
    if [[ -z "${GEN3_ENDPOINT}" ]]; then
        log "No base url set"
        exit 1
    fi

    # Gen3SDK should work if $API_KEY is set
    apikeyfile
    get_access_token

    mount_hatchery_files

    if [[ ! -d "/data/${GEN3_ENDPOINT}" ]]; then
        log "Creating /data/$GEN3_ENDPOINT/ directory"
        mkdir "/data/${GEN3_ENDPOINT}/"
    fi

    log "Trying to populate data from MDS..."
    while true; do
        populate
        # If the access token expires, fetch a new access token and try again
        if [[ $(echo "$MANIFESTS" | jq -r '.error') = "Please log in." ]]; then
            echo "Session Expired. Trying again with new access token"
            get_access_token
        else
            # log "Sleeping for 30 seconds before checking for new manifests."
            sleep 30
        fi
    done
}


main
