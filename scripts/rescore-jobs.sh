#!/bin/sh
# Recompute fit scores for all previously scored jobs using current weights and penalties.
# No LLM calls — reads stored dimensions/requirements_not_met from the database.
set -e
cd "$(dirname "$0")/.."
exec node server/rescore.js "$@"
