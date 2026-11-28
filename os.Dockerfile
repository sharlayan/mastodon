# syntax=docker/dockerfile:1.29
ARG os_version=3.10.1
FROM opensearchproject/opensearch:${os_version}
ARG os_version

RUN /usr/share/opensearch/bin/opensearch-plugin install --batch analysis-nori

HEALTHCHECK CMD curl http://localhost:9200/_cluster/health
