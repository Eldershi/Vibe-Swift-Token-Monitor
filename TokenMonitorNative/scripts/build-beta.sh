#!/bin/bash
# Compatibility entry; builds the current release.
set -euo pipefail
exec bash "$(dirname "$0")/build.sh" "$@"
