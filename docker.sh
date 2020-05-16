#!/bin/bash

docker build --tag patreon-exporter:1.0 . && \
  docker run --publish 8080:8080 --detach --name patreon-exporter patreon-exporter:1.0
