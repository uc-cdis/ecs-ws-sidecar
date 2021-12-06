FROM cfmanteiga/alpine-bash-curl-jq:latest

USER root

RUN apk add libssl-dev

WORKDIR /scripts

COPY ./sidecar.sh sidecar.sh

RUN mkdir /data


CMD [ "bash", "./sidecar.sh" ]
