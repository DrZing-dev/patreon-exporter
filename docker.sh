#!/bin/bash

docker rm --force patreon-exporter

docker build --tag patreon-exporter:1.0 . && \
  docker run --publish 8080:8080 --publish 8443:8443 --detach --name patreon-exporter patreon-exporter:1.0 && \
  docker exec -it patreon-exporter bash
