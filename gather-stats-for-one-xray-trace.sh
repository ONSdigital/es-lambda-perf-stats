#!/bin/bash

export TRACE_ID="$1"

(printf "$TRACE_ID, "; \
    aws xray batch-get-traces --region "$ARG_AWS_REGION" --trace-ids "${TRACE_ID}"  --output json --query "Traces[*].Segments[*].Document" \
        | jq -r '.[][] | fromjson | "\(.start_time   | strftime("%Y-%m-%d %H:%M:%S")), Total: \((.end_time - .start_time) * 1000 | ceil )"' \
        | gsort -t, -nrk2.8,2 | head -n 1  \
    && \
    aws xray batch-get-traces --region "$ARG_AWS_REGION" --trace-ids "${TRACE_ID}"  --output json --query "Traces[*].Segments[*].Document" \
        | jq -r '.[][] | fromjson | if (.subsegments | length ) !=0 then .subsegments[] | "\(.name) : \((.end_time - .start_time) * 1000 | ceil )"  else ""  end' \
) \
    | sort |  grep -v '^$' | paste -s -d"," -
