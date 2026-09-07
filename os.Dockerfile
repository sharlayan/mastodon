# syntax=docker/dockerfile:1.27
ARG os_version=3.7.0
FROM opensearchproject/opensearch:${os_version}
ARG os_version

RUN /usr/share/opensearch/bin/opensearch-plugin install --batch analysis-nori

HEALTHCHECK CMD curl http://localhost:9200/_cluster/health
