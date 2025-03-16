SHELL=/bin/bash
TARGETDIR:=/tmp/workspace/triggerall

# find a way to support a group
GROUPS="[a-c] [d-h] [g-l] [m-r] [s-u] [v-z]"

ALLPUBLICATIONPOINTS=$(shell find . -name "[w-z]*publication.json" )
TRIGGERALL=$(patsubst %.publication.json, %.publication.trigger, ${ALLPUBLICATIONPOINTS})

%.publication.trigger : %.publication.json
	./triggerall.sh $< $@
	cp $@ $<

all: ${TRIGGERALL}

clean:
	rm *.trigger


