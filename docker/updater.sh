#!/bin/bash

set -euo pipefail

cp -a /mojo/updater/templates/* /mojo/templates
cp -a /mojo/updater/patreon.* /mojo

exec "$@"
