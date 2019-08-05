#!/bin/bash

####### General bash settings to allow easier debugging of this script#####
set -e          # Fail fast if an error is encountered
set -o pipefail # Look at all commands in a pipeline to detect failure, not just the last
set -o functrace # Allow tracing of function calls
set -E          # Allow ERR signal to always be fired
##########################################################################

####### Error Handling ################
setOnFailureHandler() {
    local lineno=$1
    local msg=$2
    echo "Failed at $lineno: $msg"
}
trap 'setOnFailureHandler ${LINENO} "$BASH_COMMAND"' ERR
##########################################################################