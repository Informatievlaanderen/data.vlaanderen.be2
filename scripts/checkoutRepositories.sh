#!/bin/bash

PUBCONFIG=$2
ROOTDIR=$1
CONFIGDIR=$3

PROJECTDIR_DEFAULT=$( eval echo "${CIRCLE_WORKING_DIRECTORY}" )

# some test calls
#jq -r '.[] | @sh "echo \(.urlref)"' publication.config | bash -e
#jq -r '.[] | @sh "./checkout-one.sh \(.)"' publication.config | bash -e

#
# create the directory layout which allows the ea-to-rdf & the
# specgenerator to do there work:
# * src/DIR: the git repository which contains the source
# * target/DIR: the generated artificats that will be committed for publication
# * report/DIR: a directory with all intermediate and log reports to
#               understand the execution trace.  Will also be
#               committed to github, but on a separate directory so
#               that it will not be served by the proxy * the
#               implementation of the see-also rules

# use of json config files is supported by the jq tool, which is per
# default available in the circleci dockers.

# the data that is used to create the directory setup should be
# integrated with the data in the cloned repository the reason for
# this is that some data such as the navigation trail is part of the
# publication section and not of the local repository

# performance consideration: the checkout & build times might increase
# rapidely as there are many publication points to handle we coudl
# consider to create a docker with the to-be-generated situation in a
# previous state and start form that one.  The build of a new docker
# should than be done on regular time (not on every commit) e.g. 1 /
# month. And then the publication would only chekcout additonal
# publicationpoints for that month. That would reduce the runtime
# drastically.

HOSTNAME=$(jq -r .hostname ${CONFIGDIR}/config.json)

cleanup_directory() {
  rm -rf .git
  rm -rf codelijsten 

  local MAPPINGFILE=`jq -r 'if (.filename | length) > 0 then .filename else @sh "config/eap-mapping.json"  end' .publication-point.json`
  if [[ -f ".names.txt" && -f $MAPPINGFILE ]]
  then
    STR=".[] | select(.name == \"$(cat .names.txt)\") | [.]"
    jq "${STR}" ${MAPPINGFILE} >.names.json
    jq -r '.[] | @sh "find . -name \"*.eap\" !  -name \(.eap) -type f -exec rm -f {} + "' .names.json | bash -e
    SITE=`jq -r .[].site .names.json`
    find ./site-skeleton -depth -type d ! -wholename "./site-skeleton"  ! -wholename "./${SITE}" -exec rm -rf {} + 
  fi
}

git_download() {
     local GITTARGETDIR=$1

     REPO=$(_jq '.repository')
     REPO=`echo ${REPO} | sed -e "s|https://||g" | sed -e "s|/|-|g"`
     GITTMPDIR="/tmp/github/${REPO}"

     if [ ! -d ${GITTMPDIR} ] ; then
        git clone $(_jq '.repository') ${GITTMPDIR}
     fi
     pushd ${GITTMPDIR}

     if ! git checkout $(_jq '.branchtag')
     then
        # branch could not be checked out for some reason
        echo "failed: $ROOTDIR/$MAIN/$RDIR $(_jq '.branchtag')" >>$ROOTDIR/failed.txt
     fi
     cp -a ${GITTMPDIR}/. ${GITTARGETDIR}

     popd
}

construct_urlref_if_missing() {
    local pub_point_file=$1
    
    # Check if urlref is missing or empty
    if ! jq -e '.urlref and (.urlref | length > 0)' "$pub_point_file" >/dev/null 2>&1; then
        echo "urlref missing, constructing from metadata..."
        
        # Get required fields from publication point
        local name=$(jq -r '.name // empty' "$pub_point_file")
        local type=$(jq -r '.type // empty' "$pub_point_file")
        local repository=$(jq -r '.repository // empty' "$pub_point_file")
        local branchtag=$(jq -r '.branchtag // empty' "$pub_point_file")
        local filename=$(jq -r '.filename // "config/eap-mapping.json"' "$pub_point_file")
        
        if [[ -n "$repository" && -n "$branchtag" && -n "$filename" && -n "$name" ]]; then
            # Download the metadata file from the thema repository
            local temp_metadata="/tmp/metadata_${name}.json"
            ./scripts/downloadFileGithub.sh "{\"repository\":\"$repository\",\"branchtag\":\"$branchtag\",\"filepath\":\"$filename\"}" "$temp_metadata" "${TOOLCHAIN_TOKEN}"
            
            if [[ -f "$temp_metadata" ]]; then
                # Extract metadata from the thema repository
                local pub_date=$(jq -r ".[] | select(.name == \"$name\") | .publication_date // empty" "$temp_metadata")
                local pub_state=$(jq -r ".[] | select(.name == \"$name\") | .publication_state // empty" "$temp_metadata")
                
                # Construct urlref based on type
                local constructed_urlref=""
                if [[ "$type" == "ap" || "$type" == "applicatieprofiel" ]]; then
                    constructed_urlref="/doc/applicatieprofiel/${name}/${pub_state}/${pub_date}"
                elif [[ "$type" == "voc" || "$type" == "vocabularium" ]]; then
                    constructed_urlref="/doc/vocabularium/${name}/${pub_state}/${pub_date}"
                elif [[ "$type" == "im" || "$type" == "implementatiemodel" ]]; then
                    constructed_urlref="/doc/implementatiemodel/${name}/${pub_state}/${pub_date}"
                fi
                
                if [[ -n "$constructed_urlref" ]]; then
                    # Update the publication point file with the constructed urlref
                    jq --arg urlref "$constructed_urlref" '. + {urlref: $urlref}' "$pub_point_file" > "${pub_point_file}.tmp"
                    mv "${pub_point_file}.tmp" "$pub_point_file"
                    echo "Constructed urlref: $constructed_urlref"
                fi
                
                rm -f "$temp_metadata"
            fi
        fi
    fi
}


toolchainhash=$(git log | grep commit | head -1 | cut -d " " -f 2)

# Process the publications.config file
if cat ${PUBCONFIG} | jq -e . >/dev/null 2>&1
then
  # First pass: construct missing urlrefs
  # 2025/0818 - Added a preprocessing step to ensure all publication points have a valid urlref and try to construct it if missing.
  echo "Preprocessing publication points to construct missing urlrefs..."
  
  # Create a temporary file to store the updated config
  TEMP_PUBCONFIG="/tmp/processed_$(basename ${PUBCONFIG})"
  
  # Process each publication point to construct missing urlrefs
  jq -c '.[]' ${PUBCONFIG} | while IFS= read -r pub_point; do
    echo "$pub_point" > /tmp/single_pub_point.json
    construct_urlref_if_missing /tmp/single_pub_point.json
    cat /tmp/single_pub_point.json
  done | jq -s '.' > "$TEMP_PUBCONFIG"
  
  # Use the processed config for the rest of the workflow
  PUBCONFIG="$TEMP_PUBCONFIG"

  # only iterate over those that have a repository
  for row in $(jq -r '.[] | select(.repository)  | @base64 ' ${PUBCONFIG}); do
    _jq() {
      echo ${row} | base64 --decode | jq -r ${1}
    }

      FORM=$(_jq '.type')
      if [ "$FORM" == "raw" ]
      then
        MAIN=raw-input
      else
        MAIN=src
      fi

      echo "start processing (repository): $(_jq '.repository') $(_jq '.urlref') $MAIN"


      DIR=$(_jq '.urlref')
      NAME=$(_jq '.name')
      RDIR=${DIR#'/'}
      mkdir -p $ROOTDIR/$MAIN/$RDIR
      mkdir -p $ROOTDIR/target/$RDIR
      mkdir -p $ROOTDIR/report/$RDIR
      


      git_download $ROOTDIR/$MAIN/$RDIR
#      git clone $(_jq '.repository') $ROOTDIR/$MAIN/$RDIR
#
#      pushd $ROOTDIR/$MAIN/$RDIR
#      if ! git checkout $(_jq '.branchtag')
#      then
#        # branch could not be checked out for some reason
#        echo "failed: $ROOTDIR/$MAIN/$RDIR $(_jq '.branchtag')" >>$ROOTDIR/failed.txt
#      fi

      # branchtag check: if the processing is strict then the checkout of a branch is forbidden (e.g. production)
      #
      BRANCHTAG=$(_jq '.branchtag')
      ${PROJECTDIR_DEFAULT}/scripts/validateBranchtagGithub.sh $ROOTDIR/$MAIN/$RDIR ${BRANCHTAG} &> /tmp/validationBranchtag
      echo "The provided branchtag ${BRANCHTAG} is a real commit, not a branch: " 
      cat /tmp/validationBranchtag
      echo "  "
      VALIDBRANCHTAG=$( cat /tmp/validationBranchtag )
      if [ "${VALIDBRANCHTAG}" != "true" ] ; then
	      echo "Error: the branchtag ${BRANCHTAG} is a branch. It should be a real commit or tag" > ${ROOTDIR}/${MAIN}/${RDIR}/branchtag.report.md
      fi

      pushd $ROOTDIR/$MAIN/$RDIR
      

      # Save the Name points to be processed
      if [[ ! -z "$NAME" && "$NAME" != "null" ]]
      then
        echo "check name $NAME is present"
        echo "$NAME" >>.names.txt
      fi
      comhash=$(git log | grep commit | head -1 | cut -d " " -f 2)
      echo "hashcode to add: ${comhash}"
      echo ${row} | base64 --decode | jq --arg comhash "${comhash}" --arg toolchainhash "${toolchainhash}" --arg hostname "${HOSTNAME}" '. + {documentcommit : $comhash, toolchaincommit: $toolchainhash, hostname: $hostname }' > .publication-point.json
      cleanup_directory
      popd

      if [[ "$MAIN" == "src" ]]
      then
        echo "$RDIR" >>$ROOTDIR/checkouts.txt
      elif [[ "$MAIN" == "raw-input" ]]
      then
        echo "force removal of .git directory - $ROOTDIR/$MAIN/$RDIR"
        echo "$RDIR" >>$ROOTDIR/rawcheckouts.txt
        cat $ROOTDIR/rawcheckouts.txt
        rm -rf $ROOTDIR/$MAIN/$RDIR/.git
        localdirectory=$(_jq '.directory')
        if [[ "$localdirectory" != "null" ]]; then
          echo "only take the content of the directory $localdirectory"
          rm -rf /tmp/rawdir /tmp/reportdir
          mkdir -p /tmp/rawdir /tmp/reportdir
          cp -r $ROOTDIR/$MAIN/$RDIR/$localdirectory/* /tmp/rawdir
          if [ -d $ROOTDIR/$MAIN/$RDIR/report/$localdirectory/ ]
          then
            cp -r $ROOTDIR/$MAIN/$RDIR/report/$localdirectory/* /tmp/reportdir
          fi
          rm -rf $ROOTDIR/$MAIN/$RDIR/*
          cp -r /tmp/rawdir/* $ROOTDIR/$MAIN/$RDIR/
          if [ "$(ls -A /tmp/reportdir)" ]
          then
            mkdir -p $ROOTDIR/$MAIN/report/$RDIR/
            cp -r /tmp/reportdir/* $ROOTDIR/$MAIN/report/$RDIR/
          fi
        else
          echo "no localdirectory defined, keep content as is"
        fi
      fi

  done


    jq '[.[] | if has("seealso") then . else empty  end ] ' ${PUBCONFIG} > $ROOTDIR/links.txt

    if [[ -f "$ROOTDIR/failed.txt" ]]
    then
    echo "failed checking out branches"
    cat $ROOTDIR/failed.txt
    exit -1
  fi
  touch $ROOTDIR/checkouts.txt
  touch $ROOTDIR/rawcheckouts.txt
else
  echo "problem in processing: ${PUBCONFIG}"
  exit -1
fi


