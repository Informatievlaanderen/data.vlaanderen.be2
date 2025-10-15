#!/bin/bash

# This script will update publicationpoints that fullfill a certain condition
#
# The hardcoded condition is now containing "toolchain4" 
#
# The value will be todays date
#

FILE=$1
TARGET=$2
TODAY=$( date '+%Y-%m-%d %H:%M:%S') 


mkdir -p /tmp/pubpoints
TMPFILE=/tmp/pubpoints/${FILE}


jq --arg td "${TODAY}" '[.[] | if .urlref | test("toolchain4$";"i" ) then .dummy |= $td else . end ]'  ${FILE} > ${TMPFILE}
if [ -n "${TARGET}" ] ; then
	cp ${TMPFILE} ${TARGET}
else 
	cp ${TMPFILE} ${FILE}
fi


