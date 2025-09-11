SHELL=/bin/bash
TARGETDIR:=/tmp/workspace/triggerall

# find a way to support a group
GROUPS:=a-c d-h g-l m-n o-r s-u v-z

DEFAULTPUBLICATIONPOINTS:=$(shell find . -name "[a-c]*publication.json" )

TRIGGERALL=$(patsubst %.publication.json, %.publication.trigger, ${ALLPUBLICATIONPOINTS})

%.publication.trigger : %.publication.json
	./triggerall.sh $< $@
	cp $@ $<


allgroups : 
	for g in ${GROUPS}; do \
	find . -name "[$$g]*publication.json"  >> $$g.groups; \
	done

triggergroups : allgroups
	for g in ${GROUPS}; do \
	sed "s/publication.json/publication.trigger/" $$g.groups > $$g.groupstrigger ; \
	done

#
# takes one trigger group
# process it
# and then remove the group 
triggers: 
	ls -1 *groupstrigger &> /dev/null ; \
	if [ $$? -lt 1 ] ; then \
	export FILE=$(shell ls -1 *groupstrigger |head -n 1 ) ; \
	export ALLPUBLICATIONPOINTS="$$( cat $$FILE )" ; \
	make all ; \
	rm $$FILE ; fi 

nexttriggers:
	export FILE=$(shell ls -1 *groupstrigger |head -n 1 ) ; \
	echo $$FILE ; \
	rm $$FILE   




all: ${TRIGGERALL}

clean:
	rm -f *.trigger
	rm -f *.groups
	rm -f *.groupstrigger


