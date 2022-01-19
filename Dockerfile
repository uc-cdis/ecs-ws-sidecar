FROM quay.io/cdis/alpine:3.14

USER root

RUN apk update && \
    apk add --no-cache curl jq bash

WORKDIR /scripts

COPY ./sidecar.sh sidecar.sh

RUN mkdir /data


CMD [ "bash", "./sidecar.sh" ]
