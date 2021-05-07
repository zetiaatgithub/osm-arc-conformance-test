FROM golang:1.16

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git

COPY --from=lachlanevenson/k8s-kubectl:v1.10.3 /usr/local/bin/kubectl /usr/local/bin/kubectl

COPY --from=mcr.microsoft.com/azure-cli:2.20.0 /usr/local/bin/az /usr/local/bin/az

COPY ./core/osm_arc_conformance.sh /

RUN ["chmod", "+x", "/osm_arc_conformance.sh"]
ENTRYPOINT ["./osm_arc_conformance.sh"]