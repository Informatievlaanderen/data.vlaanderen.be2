SHELL=/bin/bash
TARGETDIR:=/tmp/workspace/stats

ALLSPECIFICATIONS=$(shell find . -name *.jsonld  | grep all- )
STATSPERSPECIFICATIONS=$(patsubst %.jsonld,${TARGETDIR}/%.stat,${ALLSPECIFICATIONS})
CLEANSTATSPERSPECIFICATIONS=$(patsubst %.jsonld,${TARGETDIR}/%.stat.*,${ALLSPECIFICATIONS})

rootspecifications: publication.json
	node /app/publicationpoints.js -p "#||#" -i $< -o /tmp/navigation.json
	jq . /tmp/navigation.json > ${TARGETDIR}/navigation.json
	node /app/publicationpoints.js -p "#||#" -i $< -o /tmp/rootpublicationpoints.json --rootsonly
	jq '.[]' /tmp/rootpublicationpoints.json > /tmp/rootpublicationpoints.1.json
	sed -i 's/"//g' /tmp/rootpublicationpoints.1.json
	cp /tmp/rootpublicationpoints.1.json $@
	cp $@ ${TARGETDIR}/$@

ROOTSPECIFICATIONS=$(shell cat rootspecifications)


.PHONY: allstats
allstats: ${STATSPERSPECIFICATIONS}

#	./calc_stat.sh $< ${TARGETDIR}/$(dir $@) $(notdir $@)

${TARGETDIR}/%.stat : %.jsonld
	./calc_stat.sh $< $(dir $@) $(notdir $@)

.PHONY: aggr.organisations
aggr.organisations: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.organisations  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.organisations
root.organisations: ${STATSPERSPECIFICATIONS}
	echo "[]" > $@
	for file in $^ ; \
        do \
                ./calc_support.sh $${file} $@ organisations ;\
        done
	cp $@ ${TARGETDIR}/$@


.PHONY: aggr.authors
aggr.authors: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.authors  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.authors
root.authors: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ authors ;\
	 done 
	 cp $@ ${TARGETDIR}/$@

.PHONY: aggr.editors
aggr.editors: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.editors  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.editors
root.editors: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ editors ;\
	 done 
	 cp $@ ${TARGETDIR}/$@

.PHONY: aggr.contributors
aggr.contributors: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.contributors  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.contributors
root.contributors: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ contributors ;\
	 done 
	 cp $@ ${TARGETDIR}/$@


.PHONY: aggr.class
aggr.class: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.classes  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.class
root.class: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ classes ;\
	 done 
	 cp $@ ${TARGETDIR}/$@

.PHONY: aggr.props
aggr.props: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.properties  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.props
root.props: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ properties ;\
	 done 
	 cp $@ ${TARGETDIR}/$@

.PHONY: aggr.extclass
aggr.extclass: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.externalclasses  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.extclass
root.extclass: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ externalclasses ;\
	 done 
	 cp $@ ${TARGETDIR}/$@

.PHONY: aggr.extprops
aggr.extprops: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		jq -s '.[0] + .[1].values.externalproperties  ' $@ "$${file}" >> $@.0 ;\
		mv $@.0 $@;\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.extprops
root.extprops: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
                ./calc_support.sh $${file} $@ externalproperties ;\
	 done 
	 cp $@ ${TARGETDIR}/$@

.PHONY: aggr.specstats
aggr.specstats: ${STATSPERSPECIFICATIONS}
	 echo "[]" > $@
	 for file in $^ ; \
		do \
		if [ -s $${file} ] ; then \
			jq  'del(.values) ' "$${file}" > /tmp/spec ;\
			jq -s '.[0] + [ .[1] ] ' $@ "/tmp/spec" >> $@.0 ;\
			mv $@.0 $@;\
		fi\
	 done 
	 cp $@ ${TARGETDIR}/$@
.PHONY: root.specstats
root.specstats: ${STATSPERSPECIFICATIONS}
	echo "[]" > $@
	for file in $^ ; \
                do \
                if [ -s $${file} ] ; then \
                        for root in ${ROOTSPECIFICATIONS} ; \
                        do \
                        if [[ "$${file}" =~ "$${root}" ]] ; then \
                                jq  'del(.values) ' "$${file}" > /tmp/spec ;\
                                jq -s '.[0] + [ .[1] ] ' $@ "/tmp/spec" >> $@.0 ;\
                                mv $@.0 $@;\
                                fi ; \
                        done ; \
                fi ; \
         done 
	cp $@ ${TARGETDIR}/$@


aggr.stat: aggr.organisations aggr.class aggr.props aggr.extclass aggr.extprops aggr.authors aggr.editors aggr.contributors aggr.specstats
	./calc_aggr.sh aggr ${TARGETDIR}/$@


%.voc.csv: %.voc
	jq '.[] |= {"spec": .spec, "label" : .label[0]."@value", "assignedURI": .assignedURI } ' $^ > /tmp/$@
	LLL=$$( jq 'length' /tmp/$@ ) ; echo $$LLL ; if [ $$LLL -lt 1 ] ; then echo "No values for $^" ; else \
	jq -r '(map(keys) | add | unique) as $$cols | map(. as $$row | $$cols | map($$row[.])) as $$rows | $$cols, $$rows[] | @csv' /tmp/$@ > ${TARGETDIR}/$@ ; fi
%.ap.csv: %.ap
	jq '.[] |= {"spec": .spec, "label" : .label[0]."@value", "assignedURI": .assignedURI } ' $^ > /tmp/$@
	LLL=$$( jq 'length' /tmp/$@ ) ; echo $$LLL ; if [ $$LLL -lt 1 ] ; then echo "No values for $^" ; else \
	jq -r '(map(keys) | add | unique) as $$cols | map(. as $$row | $$cols | map($$row[.])) as $$rows | $$cols, $$rows[] | @csv' /tmp/$@ > ${TARGETDIR}/$@ ; fi

ROOTS=root.classes root.properties root.externalclasses root.externalproperties
ROOTSVOC=$(patsubst %, %.voc,${ROOTS})
ROOTSAP=$(patsubst %, %.ap,${ROOTS})
ROOTSNAMED=${ROOTSVOC}
ROOTSNAMED+=${ROOTSAP}
CSVNAMED=$(patsubst %,%.csv,${ROOTSNAMED})

${ROOTSNAMED}: ${STATSPERSPECIFICATIONS}
	for file in $^ ; \
                do \
                ./calc_support2.sh $${file} $@ true true;\
         done
	for rrootfile in ${ROOTSNAMED} ; \
                do \
                if [ -f $${rrootfile} ] ; then \
                cp $${rrootfile} ${TARGETDIR} ;\
                fi ; \
         done



rootnamed.stat: ${ROOTSNAMED}
	touch rootnamed.stat
csv.stat: ${CSVNAMED}
	touch csv.stat

root.stat: root.organisations root.class root.props root.extclass root.extprops root.authors root.editors root.contributors root.specstats rootnamed.stat
	./calc_aggr.sh root ${TARGETDIR}/$@



finalize:
	for file in "${CLEANSTATSPERSPECIFICATIONS}" ; \
		do \
		rm $${file} ;\
	 done 
	cp README.statistics.md ${TARGETDIR}/README.md

print:
	echo "${CLEANSTATSPERSPECIFICATIONS}" > L
	echo "${STATSPERSPECIFICATIONS}" > LL

clean: 
	rm -rf ${STATSPERSPECIFICATIONS} 
	rm -rf ${ROOTSNAMED} 
	for file in "${CLEANSTATSPERSPECIFICATIONS}" ; \
		do \
		rm $${file} ;\
	 done 
	rm -rf csv.stat rootnamed.stat
