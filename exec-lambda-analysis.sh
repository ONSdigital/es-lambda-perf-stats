#!/bin/bash

# Uncomment this to debug script
# set -x

CONST_SCRIPT_PATH="$( cd "$(dirname "$0")" || exit ; pwd -P )"

# shellcheck source=util-err-handling.sh
source "${CONST_SCRIPT_PATH}/util-err-handling.sh"

# shellcheck source=util-colorful-logging.sh
source "${CONST_SCRIPT_PATH}/util-colorful-logging.sh"

# shellcheck source=util-functions.sh
source "${CONST_SCRIPT_PATH}/util-functions.sh"

############################# Arg parsing ############################################################

ARG_FUNCTION_NAME=
ARG_LAMBDA_MEMORY="256"
ARG_INVOKE_COUNT="5"
ARG_AWS_REGION="eu-west-2"
ARG_XRAY_PAUSE_TIME=5

CONST_START_TIMESTAMP=""

function parseArgs(){
    options=':f:m:i:r:h'
    while getopts $options option
    do
        case ${option} in
            f) # Specify Lambda Function Name (complete ARN or just name)
                ARG_FUNCTION_NAME=${OPTARG}
                ;;
            m) # OPTIONAL. Specify Memory to update the Lambda to. **Defaults to 256m**
                ARG_LAMBDA_MEMORY=${OPTARG}
                ;;
            i) # OPTIONAL. Specify Number of invocations to be done. **Defaults to 5**
                ARG_INVOKE_COUNT=${OPTARG}
                ;;
            r) # OPTIONAL. Specify AWS region. **Defaults to London (eu-west-2)**
                ARG_AWS_REGION=${OPTARG}
                ;;
            p) # OPTIONAL. Specify XRay Pause Time. **Defaults to 5 seconds**
                ARG_XRAY_PAUSE_TIME=${OPTARG}
                ;;
            h  ) usage; exit;;
            \? ) echo "Unknown option: -$OPTARG" >&2; exit 1;;
            :  ) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
            *  ) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ "x" = "x$ARG_FUNCTION_NAME" ]]; then
        echo "ARG_FUNCTION_NAME must be specified"
        exit
    fi

    echo "Setting ARG_AWS_REGION to $ARG_AWS_REGION"
    echo "Setting ARG_FUNCTION_NAME to $ARG_FUNCTION_NAME"
    echo "Setting ARG_LAMBDA_MEMORY to $ARG_LAMBDA_MEMORY"
    echo "Setting ARG_INVOKE_COUNT to $ARG_INVOKE_COUNT"
    echo "Setting ARG_XRAY_PAUSE_TIME to $ARG_XRAY_PAUSE_TIME"
}
######################## END: Arg Parsing ####################################

function displayPreamble(){
    displayHeader "Starting script at ${CONST_START_TIMESTAMP} for region ${ARG_AWS_REGION}"
}

function init(){
    displayHeader "Performing init tasks"
    defineColours
    parseArgs "$@"

    CONST_START_TIMESTAMP=$(date +%s)
    CONST_START_TIMESTAMP_FORMATTED="$(gdate -d "@${CONST_START_TIMESTAMP}" "+%Y-%m-%d_%H.%M.%S")"
    FILE_SUFFIX="${ARG_FUNCTION_NAME}_${ARG_LAMBDA_MEMORY}_${CONST_START_TIMESTAMP_FORMATTED}"
    OUTPUT_DIR="${CONST_SCRIPT_PATH}/output/${FILE_SUFFIX}"
    LAMBDA_INVOCATION_STATS="${OUTPUT_DIR}/lambda-invocation-stats-${FILE_SUFFIX}.csv"

    createDir "${OUTPUT_DIR}"
    displayPreamble
}

function updateLambda(){
    displayHeader "Updating $ARG_FUNCTION_NAME mem to $ARG_LAMBDA_MEMORY"
    aws lambda  update-function-configuration --region "${ARG_AWS_REGION}" --memory-size "${ARG_LAMBDA_MEMORY}" --function-name  "${ARG_FUNCTION_NAME}" --output table
    displayInfo "Finished updating lambda"
}

function invokeLambda(){
    displayHeader "Invoking $ARG_FUNCTION_NAME $ARG_INVOKE_COUNT times\n"
    for i in $(seq 1 "${ARG_INVOKE_COUNT}"); do printf "(%s) -->" "${i}";  aws lambda invoke --region "${ARG_AWS_REGION}" --function-name "${ARG_FUNCTION_NAME}" "${OUTPUT_DIR}/${i}_out_${FILE_SUFFIX}.txt" ;   done
    displayInfo "Finished...."
}

function pauseForXRay(){
    displayHeader " Pausing $ARG_XRAY_PAUSE_TIME seconds for x-ray to collect stats"
    sleep "${ARG_XRAY_PAUSE_TIME}"
}

function gatherStatsFromXRay(){
    displayHeader "Started Gathering Stats"
    echo "trace-id, timestamp, Total Time, Init, Invocation, Overhead" > "${LAMBDA_INVOCATION_STATS}"
    (aws xray get-trace-summaries --region "${ARG_AWS_REGION}" --start-time $((CONST_START_TIMESTAMP)) --end-time $((CONST_START_TIMESTAMP+900)) --query 'TraceSummaries[*].Id' --output json | jq -r ".[]" | xargs -I % "${CONST_SCRIPT_PATH}/gather-stats-for-one-xray-trace.sh" % | sort) >> "${LAMBDA_INVOCATION_STATS}"
    displayInfo "Finished Gathering Stats"
    displayInfo "File Created: ${LAMBDA_INVOCATION_STATS} "
}

function processCSV(){
    displayHeader "Adding missing column to CSV"
    # cat ${LAMBDA_INVOCATION_STATS} 
    awk '{ if (!/Init/) gsub("Invoc",",Invoc"); print}' < "${LAMBDA_INVOCATION_STATS}" > "${LAMBDA_INVOCATION_STATS}_temp"
    cp -r "${LAMBDA_INVOCATION_STATS}_temp" "${LAMBDA_INVOCATION_STATS}"
}

function displayCSV(){
    displayHeader "Displaying CSV file"

    if [ -x "$(command -v csvlook)" ]; then
      csvlook < "${LAMBDA_INVOCATION_STATS}"
    else
      displayErr "csvlook is not on the path. Not using it to display CSV"
    fi

    # if [ -x "$(command -v tty-table)" ]; then
      # tty-table < "${LAMBDA_INVOCATION_STATS}"
    # else
      # displayErr "tty-table is not on the path. Not using it to display CSV"
    # fi
}

function main(){
    init "$@"
    updateLambda
    invokeLambda
    pauseForXRay
    gatherStatsFromXRay
    processCSV
    displayCSV
}

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }

main "$@"
