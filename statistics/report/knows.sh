#!/bin/bash

#	jq '.[].organisations' aggr.specstats
#	jq '.[].organisations | foreach .[] as $item (0; . + 1; {source: ., $item } )' aggr.specstats
#	jq '.[].organisations as $orgs | $orgs | foreach .[] as $item (0; . + 1; {source: ., target: $orgs , $item } )' aggr.specstats > L
#	jq '[ .[].organisations as $orgs | $orgs | foreach .[] as $item (0; . + 1; {source: ., target: $orgs[0:. - 1]  , $item } ) ]' aggr.specstats > /tmp/interknows
#	jq '.[].item.affiliation as $source | .[].target | foreach .[] as $item (0; . + 1; {source: $source, target:$item.affiliation, value: $item.participants })' /tmp/interknows > L


	jq '[ .values.participants as $orgs | $orgs | foreach .[] as $item (0; . + 1; {source: ., target: $orgs[0:. - 1]  , $item } ) ]' $1 > /tmp/knows.0
	jq '[.[] as $start | $start.item.name as $source | $start.target | foreach .[] as $item (0; . + 1; {source: $source, target:$item.name, value: 1 })]' /tmp/knows.0 > /tmp/knows

	jq '[.[].item | { id: .name, group: .affiliation}]' /tmp/knows.0 > /tmp/nodes
	jq -s '{nodes: .[0], links: .[1]}' /tmp/nodes /tmp/knows


