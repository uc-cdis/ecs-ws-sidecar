FROM cfmanteiga/alpine-bash-curl-jq:latest

USER root 

WORKDIR /scripts

COPY ./sidecar.sh sidecar.sh

RUN mkdir /data


CMD [ "bash", "./sidecar.sh" ]