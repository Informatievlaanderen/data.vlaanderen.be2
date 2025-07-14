#!/bin/bash

#
# This script expects gihub cli gh being installen
# To have it working, set the GH_TOKEN environment variable.
#
# use: ./latestIssues.sh <<FILE>>

gh repo list informatievlaanderen --limit 200 --topic oslothema --json issues --json url > /tmp/repoissues
gh repo list informatievlaanderen --limit 200 --topic oslothema --json url --jq '.[].url' > /tmp/repos

TARGET=$1

REPOS=$(cat /tmp/repos)
ONEMONTHAGO=$(date -d "30 days ago" +"%Y-%m-%d")
ONEWEEKAGO=$(date -d "7 days ago" +"%Y-%m-%d")
for repo in $REPOS ; do 
	echo -n " | " >> $TARGET
	echo -n $repo >> $TARGET
	echo -n " | " >> $TARGET
	gh issue list -R $repo --json updatedAt | jq -j 'length'  >> $TARGET
	echo -n " | " >> $TARGET
        gh issue list -R $repo --json updatedAt  | jq --arg ago "${ONEMONTHAGO}T00:00:00Z" '[ .[] | .updatedAt|fromdate as $input | $ago |fromdate as $dago| if $input > $dago  then  { "updatedAt": $input|todate } else empty end ]' | jq -j 'length' >> $TARGET
	echo -n " | " >> $TARGET
        gh issue list -R $repo --json updatedAt  | jq --arg ago "${ONEWEEKAGO}T00:00:00Z" '[ .[] | .updatedAt|fromdate as $input | $ago |fromdate as $dago| if $input > $dago  then  { "updatedAt": $input|todate } else empty end ]'  | jq -j 'length' >> $TARGET
	echo " | " >> $TARGET
done

