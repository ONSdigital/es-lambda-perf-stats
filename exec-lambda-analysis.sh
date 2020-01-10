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
ARG_INVOKE_COUNT="8"
ARG_AWS_REGION="eu-west-2"
ARG_XRAY_PAUSE_TIME=10

CONST_START_TIMESTAMP=""
CONST_END_TIMESTAMP=""

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

    IFS=',' read -r -a mem_array <<< "$ARG_LAMBDA_MEMORY"
    # for element in "${mem_array[@]}"
    # do
        # echo "Mem: $element"
    # done
    mem_array_length="${#mem_array[*]}"
    printf "mem_array_length : %s\n" "$mem_array_length"

    # for i in $(seq 0 $(( ARG_INVOKE_COUNT - 1 )) ); do
        # chosen_mem_array_index=$(( i % mem_array_length))
        # printf "chosen_mem_array_index : %s\n" "${chosen_mem_array_index}"
        # echo "Invocation $i will use mem_array[${chosen_mem_array_index}] with value ${mem_array[${chosen_mem_array_index}]}" 
    # done
}
######################## END: Arg Parsing ####################################

function displayPreamble(){
    displayHeader "Starting script at ${CONST_START_TIMESTAMP} for region ${ARG_AWS_REGION}"
}

function init(){
    displayHeader "Performing init tasks"
    defineColours
    parseArgs "$@"

    CONST_START_TIMESTAMP="$(date +%s)"
    CONST_START_TIMESTAMP_FORMATTED="$(gdate -d "@${CONST_START_TIMESTAMP}" "+%Y-%m-%d_%H.%M.%S")"
    FILE_SUFFIX="${ARG_FUNCTION_NAME}_${ARG_LAMBDA_MEMORY}_${CONST_START_TIMESTAMP_FORMATTED}"
    OUTPUT_DIR="${CONST_SCRIPT_PATH}/output/${FILE_SUFFIX}"
    LAMBDA_INVOCATION_STATS="${OUTPUT_DIR}/lambda-invocation-stats-${FILE_SUFFIX}.csv"

    createDir "${OUTPUT_DIR}"
    displayPreamble
}

function updateLambda(){
    local __local_function_name="${1}"
    local __local_function_mem="${2}"

    displayHeader "Updating $__local_function_name mem to $__local_function_mem"
    aws lambda  update-function-configuration --region "${ARG_AWS_REGION}" --memory-size "${__local_function_mem}" --function-name  "${__local_function_name}" --output text 1>/dev/null
    # displayHeader "Finished updating $__local_function_name mem to $__local_function_mem"
}

function invokeLambda(){
    displayHeader "Invoking $ARG_FUNCTION_NAME $ARG_INVOKE_COUNT times\n"

    CONST_START_TIMESTAMP="$(( $(date +%s)-1 ))"
    for i in $(seq 0 $(( ARG_INVOKE_COUNT - 1 )) ); do
        chosen_mem_array_index=$(( i % mem_array_length))
        chosen_mem="${mem_array[${chosen_mem_array_index}]}"
        # printf "chosen_mem_array_index : %s\n" "${chosen_mem_array_index}"

        echo "Invocation $i will use mem_array[${chosen_mem_array_index}] with value ${chosen_mem} " 
        updateLambda "${ARG_FUNCTION_NAME}" "${chosen_mem}"

        printf "(%s) -->" "${i}";  aws lambda invoke --region "${ARG_AWS_REGION}" --function-name "${ARG_FUNCTION_NAME}" "${OUTPUT_DIR}/${i}_out_${FILE_SUFFIX}.txt" ;
        displayInfo "Finished invocation num $i ..."
    done

    CONST_END_TIMESTAMP="$(date +%s)"
    displayInfo "Finished all ${ARG_INVOKE_COUNT} invocations....at ${CONST_END_TIMESTAMP}"
}

function pauseForXRay(){
    displayHeader " Pausing $ARG_XRAY_PAUSE_TIME seconds for x-ray to collect stats"
    sleep "${ARG_XRAY_PAUSE_TIME}"
}

function execute_trace_summary(){
    echo "Executing xray on $(gdate) " >&2 
    echo aws xray get-trace-summaries --region "${ARG_AWS_REGION}" --start-time "$CONST_START_TIMESTAMP" --end-time "$CONST_END_TIMESTAMP" --query 'TraceSummaries[*].Id' --output json  >&2

    aws xray get-trace-summaries --region "${ARG_AWS_REGION}" --start-time "$CONST_START_TIMESTAMP" --end-time "$CONST_END_TIMESTAMP"  --query 'TraceSummaries[*].Id' --output json 
}

function gatherStatsFromXRay(){
    displayHeader "Waiting for all stats to be present in X-Ray"

    local TRACE_SUMMARY_OUTPUT=""
    local TRACE_IDS=""
    local TRACE_IDS_COUNT=0

    while [[  TRACE_IDS_COUNT -lt ARG_INVOKE_COUNT  ]] ; do 
        # aws logs get-query-results --query-id "${AWS_LOG_QUERY_ID}" --output json | jq -r ".status" | grep -q -i "complete" && break || echo "Waiting for ${AWS_LOG_QUERY_ID} to finish"
        TRACE_SUMMARY_OUTPUT="$(execute_trace_summary)"

        TRACE_IDS="$(echo "${TRACE_SUMMARY_OUTPUT}"| jq -r ".[]" )"
        TRACE_IDS_COUNT="$(echo "${TRACE_SUMMARY_OUTPUT}"| jq -r ".| length" )"
        displayInfo "Getting details for traces:\n ${TRACE_IDS}"
        echo "Waiting for X-Ray. Expected length : ${ARG_INVOKE_COUNT}, Current length is : ${TRACE_IDS_COUNT}"

        sleep 1
    done

    displayInfo "Getting details for traces:\n ${TRACE_IDS}"

    echo "trace-id, timestamp, Total Time, Init, Invocation, Overhead" > "${LAMBDA_INVOCATION_STATS}"
    printf "%s" "$(export ARG_AWS_REGION && echo "${TRACE_IDS}" | xargs -I % "${CONST_SCRIPT_PATH}/gather-stats-for-one-xray-trace.sh" % | sort)" | tee -a "${LAMBDA_INVOCATION_STATS}"

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
    invokeLambda
    gatherStatsFromXRay
    processCSV
    displayCSV
}

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }

main "$@"
