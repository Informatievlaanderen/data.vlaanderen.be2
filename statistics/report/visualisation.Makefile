SHELL=/bin/bash
TARGETDIR:=/tmp/workspace/stats

ALLSPECIFICATIONS=$(shell find . -name "*.stat"  | grep all- )
KNOWSSPECIFICATIONS=$(patsubst %.stat,${TARGETDIR}/%.knows,${ALLSPECIFICATIONS})



knowsall: ${KNOWSSPECIFICATIONS}
	for file in  ${KNOWSSPECIFICATIONS} ; do \
	   echo $$file ; \
	   jq -s '.[0].nodes +  .[1].nodes | unique' ./all.knows $$file > /tmp/all.nodes  ;\
	   jq -s '.[0].links +  .[1].links | unique ' ./all.knows $$file > /tmp/all.links  ;\
	   jq -s '{nodes: .[0], links: .[1]}' /tmp/all.nodes /tmp/all.links > all.knows ;\
	done

${TARGETDIR}/%.knows: %.stat
	mkdir -p $(dir $@)
	./knows.sh $< > $@


clean: 
	rm -rf ${KNOWSSPECIFICATIONS}
