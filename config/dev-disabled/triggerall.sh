#!/bin/bash

# This script will update ALL publicationpoints 
#
# The value will be today's date, triggering a rebuild for all publication points
# This is intended for use in weekly CircleCI scheduled runs
#

FILE=$1
TARGET=$2
TODAY=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p /tmp/pubpoints
TMPFILE=/tmp/pubpoints/$(basename ${FILE})

# Update dummy field for ALL publication points (remove the urlref filter)
jq --arg td "${TODAY}" '[.[] | .dummy |= $td]' ${FILE} > ${TMPFILE}

if [ -n "${TARGET}" ]; then
    cp ${TMPFILE} ${TARGET}
else 
    cp ${TMPFILE} ${FILE}
fi