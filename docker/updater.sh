#!/bin/bash

set -euo pipefail

cp -a /mojo/updater/templates/* /mojo/templates
cp -a /mojo/updater/patreon.* /mojo

hypnotoad /mojo/patreon.pl

# Keep the container running
trap : TERM INT; sleep infinity & wait
