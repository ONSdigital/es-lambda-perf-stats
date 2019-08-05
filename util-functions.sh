#!/bin/bash

function createDir(){
    local message="Creating ${1}" 
    function_exists displayHeader && displayHeader "${message}" || echo "${message}"
    mkdir -p "${1}"
}

function_exists() {
    declare -f -F "${1}" > /dev/null
    return $?
}