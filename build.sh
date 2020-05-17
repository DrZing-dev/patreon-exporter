#!/bin/bash

docker rm --force patreon-exporter

SRCDIR=$(dirname "$(realpath $0)")

echo $SRCDIR

docker build --tag patreon-exporter:1.0 . && \

docker run --publish 8080:8080 --publish 8443:8443 \
  --detach \
  --mount type=bind,source=$SRCDIR,target=/mojo/updater \
  --name patreon-exporter patreon-exporter:1.0

docker exec -it patreon-exporter bash

if [ $? -ne 0 ]; then
  docker logs patreon-exporter
fi
