function log(){
    LOGFILE="/data/populate_log.txt"
    if [[ ! -f ${LOGFILE} ]]; then
        touch ${LOGFILE}
    fi
    TIMESTAMP=`date "+%Y-%m-%d %H:%M:%S"`
    echo "${TIMESTAMP}: $1"
    echo "${TIMESTAMP}: $1" >> ${LOGFILE}
}

# Shouldn't this be a function?
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
    log "querying manifest service at $GEN3_ENDPOINT/metadata/"
    METADATA=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/metadata/")

    while [ -z "$MANIFESTS" ] || [ -z "$METADATA" ]; do
        if [ -z "$MANIFESTS" ]; then
            log "Unable to get manifests from '$GEN3_ENDPOINT/manifests/'"
            log $MANIFESTS
        fi
        if [ -z "$METADATA" ]; then
            log "Unable to get metadata from '$GEN3_ENDPOINT/metadata/'"
            log $METADATA
        fi
        log "sleeping for 15 seconds before trying again.."
        sleep 15
        MANIFESTS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/")
        METADATA=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/metadata/")
    done
    log "successfully retrieved manifests and metadata for user"

    process_files() {
        local data=$1
        local base_dir=$2

        echo $data | jq -c '.[]' | while read i; do
        FILENAME=$(echo "${i}" | jq -r .filename)
        FOLDERNAME=$(echo "${FILENAME%.*}")
        FOLDER="/data/${GEN3_ENDPOINT}/exported-${base_dir}/exported-${FOLDERNAME}"

        if [ ! -d "$FOLDER" ]; then
            log "mkdir -p $FOLDER"
            mkdir -p $FOLDER

            # make sure folder can be written to by notebook
            chown -R 1000:100 $FOLDER

            if ["$base_dir" == "manifests"];then
                MANIFEST=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/file/$FILENAME")
                echo "${MANIFEST}" > $FOLDER/manifest.json
                log "Creating notebook for $FILENAME"
                cp ./template_manifest.json $FOLDER/data.ipynb
                populate_notebook "$MANIFEST" "$FOLDER"
            elif ["$base_dir" == "metadata"];then
                METADATA=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/metadata/$FILENAME")
                echo "${METADATA}" > $FOLDER/metadata.json
            fi
        fi
        done
    }

    echo $MANIFESTS | jq -c '.manifests' | process_files manifests
    echo $METADATA | jq -c '.external_file_metadata' | process_files metadata

    # #  Loop over each exported manifest
    # echo $MANIFESTS | jq -c '.manifests[]' | while read i; do
    #     FILENAME=$(echo "${i}" | jq -r .filename)
    #     FOLDERNAME=$(echo "${FILENAME%.*}")
    #     FOLDER="/data/${GEN3_ENDPOINT}/exported-${FOLDERNAME}"
    #     # /data/${GEN3_ENDPOINT}/exported-manifests/exported-${FOLDERNAME}
    #     # /data/${GEN3_ENDPOINT}/exported-metadata/exported-${FOLDERNAME}
    #     # ^ only need to put in the metadata.json
    #     if [ ! -d "$FOLDER" ]; then
    #         log "mkdir -p $FOLDER"
    #         mkdir -p $FOLDER

    #         # make sure folder can be written to by notebook
    #         chown -R 1000:100 $FOLDER
    #         MANIFEST=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/manifests/file/$FILENAME")
    #         echo "${MANIFEST}" > $FOLDER/manifest.json
    #         # only need to do this part for metadata ^ not this part v

    #         log "Creating notebook for $FILENAME"
    #         cp ./template_manifest.json $FOLDER/data.ipynb
    #         populate_notebook "$MANIFEST" "$FOLDER"
    #     fi
    # done

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

function get_gen3_access_token() {
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

function get_manifest_service_access_token() {
    log "Getting access token"
    ACCESS_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST "https://$GEN3_ENDPOINT/user/credentials/api/access_token/" -d "{ \"api_key\": \"${API_KEY}\" }" | jq -r .access_token)
}

function mount_hatchery_files() {
    log "Mounting Hatchery files"
    FOLDER="/data"
    if [ ! -d "$FOLDER" ]; then
        mkdir $FOLDER
    fi

    echo "Fetching files to mount..."
    echo "This workspace flavor is '$WORKSPACE_FLAVOR'"
    DATA=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/lw-workspace/mount-files")
    echo $DATA | jq -c -r '.[]' | while read item; do
        file_path=$(echo "${item}" | jq -r .file_path)
        workspace_flavor=$(echo "${item}" | jq -r .workspace_flavor)
        # mount the file if its workspace flavor is not set or if it matches the current workspace flavor
        if [[ -z "${workspace_flavor}" || -z "${WORKSPACE_FLAVOR}" || $workspace_flavor == $WORKSPACE_FLAVOR ]]; then
            echo "Mounting '$file_path'"
            mkdir -p "$FOLDER/$(dirname "$file_path")"
            curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://$GEN3_ENDPOINT/lw-workspace/mount-files?file_path=$file_path" > $FOLDER/$file_path
        else
            echo "Not mounting '$file_path' because its workspace flavor '$workspace_flavor' does not match"
        fi
    done

    # Make sure notebook user has write access to the folders
    chown -R 1000:100 $FOLDER
}

function main() {
    if [[ -z "${GEN3_ENDPOINT}" ]]; then
        log "No base url set"
        exit 1
    fi

    if [[ -z "${MANIFEST_SERVICE_ENDPOINT}" ]]; then
        log "Manifest service url not set"
        exit 1
    fi

    # Gen3SDK should work if $API_KEY is set
    apikeyfile
    get_gen3_access_token
    get_manifest_service_access_token

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
            get_gen3_access_token
        else
            # log "Sleeping for 30 seconds before checking for new manifests."
            sleep 30
        fi
    done
}


main
