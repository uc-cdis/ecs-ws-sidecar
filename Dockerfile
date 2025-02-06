FROM quay.io/cdis/alpine:3.21.2

USER root

RUN apk update && \
    apk add --no-cache curl jq bash

WORKDIR /scripts

COPY ./sidecar.sh sidecar.sh
COPY ./template_manifest.json template_manifest.json

RUN mkdir /data


CMD [ "bash", "./sidecar.sh" ]
