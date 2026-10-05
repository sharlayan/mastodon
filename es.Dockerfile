# syntax=docker/dockerfile:1.27
ARG es_version=8.19.15
FROM docker.elastic.co/elasticsearch/elasticsearch:${es_version}
ARG es_version

RUN /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch analysis-nori

HEALTHCHECK CMD curl http://localhost:9200/_cluster/health
