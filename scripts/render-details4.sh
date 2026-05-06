#!/bin/bash

TARGETDIR=$1
DETAILS=$2
CONFIGDIR=$3

PRIMELANGUAGECONFIG=$(jq -r .primeLanguage ${CONFIGDIR}/config.json)
GOALLANGUAGECONFIG=$(jq -r '.otherLanguages | @sh' ${CONFIGDIR}/config.json)
GOALLANGUAGECONFIG=$(echo ${GOALLANGUAGECONFIG} | sed -e "s/'//g")

PRIMELANGUAGE=${4-${PRIMELANGUAGECONFIG}}
GOALLANGUAGE=${5-${GOALLANGUAGECONFIG}}

STRICT=$(jq -r .toolchain.strickness ${CONFIGDIR}/config.json)
HOSTNAME=$(jq -r .hostname ${CONFIGDIR}/config.json)
URIDOMAIN=$(jq -r .domain ${CONFIGDIR}/config.json)

CHECKOUTFILE=${TARGETDIR}/checkouts.txt
export NODE_PATH=/app/node_modules

AUTOTRANSLATIONDIR=${TARGETDIR}/autotranslation

REPORTLINEPREFIX='#||# '
REPORTLINENEWLINE='  '

execution_strickness() {
    if [ "${STRICT}" != "lazy" ]; then
        exit -1
    fi
}

generator_parameters() {
    
    local GENERATOR=$1
    local JSONI=$2
    
    #
    # The toolchain can add specific parameters for the SHACL generation tool
    # Priority rules are as follows:
    #   1. publication point specific
    #   2. generic configuration
    #   3. otherwise empty string
    #
    COMMAND=$(echo '.'${GENERATOR}'.parameters')
    PARAMETERS=$(jq -r ${COMMAND} ${JSONI})
    if [ "${PARAMETERS}" == "null" ]; then
        PARAMETERS=$(jq -r ${COMMAND} ${CONFIGDIR}/config.json)
    fi
    if [ "${PARAMETERS}" == "null" ] || [ -z "${PARAMETERS}" ]; then
        PARAMETERS=""
    fi
}

generate_for_language() {
    
    local LANGUAGE=$1
    local JSONI=$2
    
    #
    # test if the generator should be executed for this language
    #
    # if config.toolchain.autotranslate = true then apply the generator for any language in config.otherLanguages
    # if config.toolchain.autotranslate = false then apply the generator if the JSONI.translation contains the language
    # otherwise false
    #
    AUTOTRANSLATE=$(jq -r .toolchain.autotranslate ${CONFIGDIR}/config.json)
    
    if [ ${AUTOTRANSLATE} == true ]; then
        
        OTHERCOMMAND=$(echo '.otherLanguages | contains(["'${LANGUAGE}'"])')
        OTHER=$(jq -r "${OTHERCOMMAND}" ${CONFIGDIR}/config.json)
        if [ "${OTHER}" == "true" ] || [ "${OTHER}" == true ]; then
            GENERATEDARTEFACT=true
        else
            GENERATEDARTEFACT=false
        fi
    else
        COMMANDLANGJSON=$(echo '.translation | .[] | select(.language | contains("'${LANGUAGE}'")) | .translationjson')
        TRANSLATIONFILE=$(jq -r "${COMMANDLANGJSON}" ${JSONI})
        if [ "${TRANSLATIONFILE}" == "" ] || [ "${TRANSLATIONFILE}" == "null" ]; then
            GENERATEDARTEFACT=false
        else
            GENERATEDARTEFACT=true
        fi
        
    fi
    
}


check_tool_output_for_non_emptiness() {
    local REPORT=$1
    
    sed "/${REPORTLINEPREFIX}/d" $REPORT >/tmp/out
    # if the report is empty then sun (no issues)
    # if the report contains indications of errors (word Error, error) then thunderstorm
    # if the report contains indications of warnings (word Warning, warning) then cloud
    # otherwise sun
    SUN="&#9728;"
    CLOUD="&#9729;"
    THUNDERSTORM="&#9736;"
    
    if [ -s /tmp/out ]; then
        E=$(grep -ci '\berror\b' /tmp/out)
        if [ $E -gt 0 ]; then
            REPORTSTATE=${THUNDERSTORM}
        else
            W=$(grep -ci '\bwarn\b' /tmp/out)
            if [ $W -gt 0 ]; then
                REPORTSTATE=${CLOUD}
            else
                REPORTSTATE=${SUN}
            fi
        fi
    else
        REPORTSTATE=${SUN}
    fi
}

render_report_header() {
    local OVERVIEW=$1
    
    if [ ! -f ${OVERVIEW} ]; then
        echo "### Legende" >${OVERVIEW}
        echo "" >>${OVERVIEW}
        echo "<details>" >>${OVERVIEW}
        echo "" >>${OVERVIEW}
        echo "| Term | Betekenis |" >>${OVERVIEW}
        echo "| --- | --- |" >>${OVERVIEW}
        declare -A terms
        terms=(
            ["tag"]="Branchtag check"
            ["uml"]="Extraction of the data out of the UML"
            ["val"]="Validate the jsonld"
            ["stak"]="Validate and convert the stakeholders"
            ["trns"]="Translation files generation, based on existing translation files"
            ["aut"]="Autotranslate the translation files, if active"
            ["mrg"]="Merge translations to create for each language a single source of truth"
            ["web"]="Extract all data model for html rendering "
            ["met"]="Extract metadata for html rendering"
            ["html"]="Render html using generic nunjuncks"
            ["rspc"]="Render html using specific RESPEC integration "
            ["ctx"]="JSON-LD Context file generation"
            ["rdf"]="RDF file generation"
            ["shcl"]="SHACL file generation"
            ["swag"]="Swagger file generation"
            ["bundle"]="Resource bundling"
            ["issu"]="Open Issues"
        )
        
        for term in "${!terms[@]}"; do
            echo "| $term | ${terms[$term]} |" >>${OVERVIEW}
        done
        
        # End of legende
        echo "" >>${OVERVIEW}
        echo "</details>" >>${OVERVIEW}
        echo "" >>${OVERVIEW}
        
        echo "| Specification | tag | uml | val | stak | trns | aut  | mrg | web | met | html | rspc| ctx | rdf | shcl | swag | bundle | issu |" >>${OVERVIEW}
        echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |" >>${OVERVIEW}
        
    fi
}

render_report_line() {
    echo "add report overview for $1"
    local LINE=$1
    local RLINE=$2
    local JSONI=$3
    local EXECUTIONVIEW=$4
    local OLD_GLOBAL_OVERVIEW=$5
    local GLOBAL_OVERVIEW=$6
    
    render_report_header ${EXECUTIONVIEW}
    local FIRSTPARTLINE=$(echo $LINE | cut -d'/' -f2-3)
    local SECONDPARTLINE=$(echo $LINE | cut -d'/' -f4-)
    HOSTNAME=$(jq -r .hostname ${JSONI})
    URLREF=$(jq -r .urlref ${JSONI})
    echo -n "| [${FIRSTPARTLINE}/ ${SECONDPARTLINE}](${HOSTNAME}${URLREF}) <br/> [&#9883;](/report4/${LINE}) [&#9884;](${HOSTNAME}${URLREF})" >>${EXECUTIONVIEW}
    
    REPORTS="branchtag oslo-converter-ea jsonld-validation oslo-stakeholders-converter translate autotranslate merge generator-webuniversum-json metadata generator-html generator-respec generator-jsonld-context generator-rdf generator-shacl generator-swagger bundle"
    
    for REPORTFILE in ${REPORTS}; do
        REPORTPATH=${RLINE}/${REPORTFILE}.report.md
        REPORTLINK=/report4/${LINE}/${REPORTFILE}.report.md
        if [ "${REPORTFILE}" == "bundle" ] && [ ! -f "${REPORTPATH}" ] && [ -f "${RLINE}/bundle.report.md" ]; then
            REPORTPATH=${RLINE}/bundle.report.md
            REPORTLINK=/report4/${LINE}/bundle.report.md
        fi
        if [ -f ${REPORTPATH} ]; then
            check_tool_output_for_non_emptiness ${REPORTPATH}
            echo -n "| [${REPORTSTATE}](${REPORTLINK})" >>${EXECUTIONVIEW}
        else
            echo -n "| " >>${EXECUTIONVIEW}
        fi
    done
    
    # process the issues
    #
    REPOSITORY=$(jq -r .repository ${JSONI})
    FEEDBACKURL=$(jq -r .feedbackurl ${JSONI})
    if [ "${REPOSITORY}/issues" == "${FEEDBACKURL}" ]; then
        echo ""
    else
        echo "WARNING: feedback url and thema repository differ"
        echo "       REPOSITORY > ${REPOSITORY}/issues"
        echo "       FEEDBACK   > ${FEEDBACKURL}"
    fi
    
    ${PWD}/scripts/countRepoIssues.sh ${REPOSITORY} /tmp/issues
    NBIssues=$(cat /tmp/issues)
    echo -n "| [ ${NBIssues} ](${REPOSITORY}/issues)" >>${EXECUTIONVIEW}
    
    # end processing issues
    
    echo "|" >>${EXECUTIONVIEW}
    
    # Merge old and new overview
    if ! node /app/merge-overviewreport.js -p ${OLD_GLOBAL_OVERVIEW} -c ${EXECUTIONVIEW} -o ${GLOBAL_OVERVIEW}; then
        echo "RENDER-DETAILS: failed"
        execution_strickness
    else
        echo "RENDER-DETAILS: overview merged succesfully"
        pretty_print_json ${OUTPUTTRANSLATIONFILE} # What is this doing? Relict?
    fi
    
    for REPORTFILE in ${REPORTS}; do
        REPORTPATH=${RLINE}/${REPORTFILE}.report.md
        if [ "${REPORTFILE}" == "bundle" ] && [ ! -f "${REPORTPATH}" ] && [ -f "${RLINE}/bundle.report.md" ]; then
            REPORTPATH=${RLINE}/bundle.report.md
        fi
        if [ -f ${REPORTPATH} ]; then
            LINK=$(basename $JSONI)
            node /app/report_lines_links.js -i ${JSONI} -o /tmp/reportlines
            REF=$(basename ${JSONI})
            sed -E "s|(urn:.*) = (.*)|s \1 [\1](${REF}#L\2) g|g " /tmp/reportlines >/tmp/markdown_report_lines
            cat /tmp/markdown_report_lines | while read line; do
                sed -i -E "$line" ${REPORTPATH}
            done
            #markdown friendly
            sed -i "s/$/\n/" ${REPORTPATH}
        fi
    done
}

#
# need to be called once instead for each
consolidate_reporting() {
    echo "consolidate reporting $1"
    local RLINE=$1
    
    # Check if the directories exist
    if [ -d "${RLINE}/context" ]; then
        cp -r ${RLINE}/context/* ${RLINE}
        rm -rvf ${RLINE}/context
    else
        echo "No context directory found"
    fi
    if [ -d "${RLINE}/rdf" ]; then
        cp -r ${RLINE}/rdf/* ${RLINE}
        rm -rvf ${RLINE}/rdf
    else
        echo "No rdf directory found"
    fi
    if [ -d "${RLINE}/html" ]; then
        cp -r ${RLINE}/html/* ${RLINE}
        rm -rf ${RLINE}/html
    else
        echo "No html directory found"
    fi
    if [ -d "${RLINE}/respec" ]; then
        cp -r ${RLINE}/respec/* ${RLINE}
        rm -rf ${RLINE}/respec
    else
        echo "No respec directory found"
    fi
    if [ -d "${RLINE}/shacl" ]; then
        cp -r ${RLINE}/shacl/* ${RLINE}
        rm -rf ${RLINE}/shacl
    else
        echo "No shacl directory found"
    fi
    if [ -d "${RLINE}/jsonld-validation" ]; then
        echo "jsonld-validation directory found"
        
        cp -r ${RLINE}/jsonld-validation/* ${RLINE}
        rm -rf ${RLINE}/jsonld-validation
    else
        echo "No jsonld-validation directory found"
    fi
}

render_merged_files() {
    echo "Merge the translation file for language $2 with the source $3"
    local PRIMELANGUAGE=$1
    local GOALLANGUAGE=$2
    local JSONI=$3
    local SLINE=$4
    local TLINE=$5
    local RLINE=$6
    
    FILENAME=$(jq -r ".name" ${JSONI})
    GOALFILENAME=${FILENAME}_${GOALLANGUAGE}.json
    
    COMMANDLANGJSON=$(echo '.translation | .[] | select(.language | contains("'${GOALLANGUAGE}'")) | .autotranslate')
    USEAUTOTRANSLATION=$(jq -r "${COMMANDLANGJSON}" ${JSONI})
    TRANSLATIONFILE=${GOALFILENAME}
    
    REPORTFILE=${TLINE}/merge.report.md
    echo "${REPORTLINEPREFIX}merge for language ${GOALLANGUAGE} ${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    
    # secure the case that the translation file is not mentioned
    if [ "${USEAUTOTRANSLATION}" == "" ] || [ "${USEAUTOTRANSLATION}" == "null" ]; then
        INPUTTRANSLATIONFILE=${TLINE}/translation/${TRANSLATIONFILE}
    else
        if [ "${USEAUTOTRANSLATION}" == true ]; then
            AUTOTRANSLATE=$(jq -r .toolchain.autotranslate ${CONFIGDIR}/config.json)
            if [ ${AUTOTRANSLATE} == true ]; then
                INPUTTRANSLATIONFILE=${TLINE}/autotranslation/${TRANSLATIONFILE}
            else
                INPUTTRANSLATIONFILE=${TLINE}/translation/${TRANSLATIONFILE}
            fi
        else
            INPUTTRANSLATIONFILE=${TLINE}/translation/${TRANSLATIONFILE}
        fi
    fi
    
    if [ -f "${INPUTTRANSLATIONFILE}" ]; then
        echo "A translation file ${TRANSLATIONFILE} exists."
        # This should be revisited with autotranslation persistence at the right moment
        sed -i -e "s/${GOALLANGUAGE}-t-${PRIMELANGUAGE}/${GOALLANGUAGE}/g" ${INPUTTRANSLATIONFILE}
    fi
    
    mkdir -p ${RLINE}/merged
    MERGEDFILENAME=merged_${FILENAME}_${GOALLANGUAGE}.jsonld
    MERGEDFILE=${RLINE}/merged/${MERGEDFILENAME}
    
    if [ "${PRIMELANGUAGE}" == "${GOALLANGUAGE}" ]; then
        echo "The primelanguage and the goallanguage are the same:  nothing to merge. Just copy it"
        cp ${JSONI} ${MERGEDFILE}
        
    else
        if [ -f "${INPUTTRANSLATIONFILE}" ]; then
            echo "${INPUTTRANSLATIONFILE} exists, the files will be merged."
            echo "RENDER-DETAILS(mergefile): node /app/translation-json-update.js -i ${JSONI} -f ${TRANSLATIONFILE} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${MERGEDFILE} -p ${REPORTLINEPREFIX}"
            if ! node /app/translation-json-update.js -i ${JSONI} -f ${INPUTTRANSLATIONFILE} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${MERGEDFILE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
                echo "RENDER-DETAILS: failed"
                execution_strickness
            else
                echo "RENDER-DETAILS: Files succesfully merged and saved to: ${MERGEDFILE}"
                prettyprint_jsonld ${MERGEDFILE}
            fi
        else
            echo "${INPUTTRANSLATIONFILE} does not exist, nothing to merge. Just copy it"
            cp ${JSONI} ${MERGEDFILE}
        fi
    fi
}

render_metadata() {
    echo "create metadata for language $1 for $2 in the directory $5"
    local GOALLANGUAGE=$1
    local JSONI=$2
    local DROOT=$3
    local SLINE=$4
    local TLINE=$5
    
    FILENAME=$(jq -r ".name" ${JSONI})
    METAOUTPUTFILENAME=meta_${FILENAME}_${GOALLANGUAGE}.json
    mkdir -p ${TLINE}/html
    METAOUTPUT=${TLINE}/html/${METAOUTPUTFILENAME}
    
    REPORTFILE=${TLINE}/metadata.report.md
    echo "${REPORTLINEPREFIX}metadata for language ${GOALLANGUAGE} ${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    
    if ! node /app/html-metadata-generator.js -i ${JSONI} -g ${PRIMELANGUAGE} -m ${GOALLANGUAGE} -h ${HOSTNAME} -r /${DROOT} -u ${URIDOMAIN} -o ${METAOUTPUT} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
        echo "RENDER-DETAILS: failed"
        execution_strickness
    else
        echo "RENDER-DETAILS: metadata file succesfully updated"
        pretty_print_json ${METAOUTPUT}
    fi
    
}

validate_jsonld() {
    echo "validate jsonld: $1 $2 $3 $4"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    
    MERGEDFILE=${JSONI}
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    
    case $TYPE in
        ap)
            SPECTYPE="ApplicationProfile"
        ;;
        voc)
            SPECTYPE="Vocabulary"
        ;;
        oj)
            SPECTYPE="ApplicationProfile"
        ;;
        *)
            echo "ERROR: ${SPECTYPE} not recognized"
            SPECTYPE="ApplicationProfile"
        ;;
    esac
    
    
    mkdir -p ${RLINE}
    
    REPORTFILE=${RLINE}/jsonld-validation.report.md
    echo "${REPORTLINEPREFIX}oslo-jsonld-validator ${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    
    oslo-jsonld-validator --input ${MERGEDFILE} \
    --whitelist https://raw.githubusercontent.com/Informatievlaanderen/OSLO-UML-Transformer/refs/heads/configuration/whitelist.json \
    --specificationType ${SPECTYPE} \
    2>&1 | tee -a ${REPORTFILE}
    
    echo ${REPORTFILE}
    echo "RENDER-DETAILS(JSONLD-VALIDATION): File was rendered in ${REPORTFILE}"
}

render_translationfiles() {
    echo "create template translations for primelanguage $1 to goallanguage $2 and input $3 in the directory $4"
    local PRIMELANGUAGE=$1
    local GOALLANGUAGE=$2
    local JSONI=$3
    local SLINE=$4
    local TLINE=$5
    
    FILENAME=$(jq -r ".name" ${JSONI})
    PRIMEOUTPUTFILENAME=${FILENAME}_${PRIMELANGUAGE}.json
    GOALOUTPUTFILENAME=${FILENAME}_${GOALLANGUAGE}.json
    
    # XXX this block can be removed
    COMMANDLANGJSON=$(echo '.translation | .[] | select(.language | contains("'${GOALLANGUAGE}'")) | .translationjson')
    LANGUAGEINTHEMA=$(jq -r "${COMMANDLANGJSON}" ${JSONI})
    # secure the case that the translation file is not mentioned
    if [ "${LANGUAGEINTHEMA}" == "" ] || [ "${LANGUAGEINTHEMA}" == "null" ]; then
        TRANSLATIONFILE=${GOALOUTPUTFILENAME}
    else
        TRANSLATIONFILE=${GOALOUTPUTFILENAME}
    fi
    
    mkdir -p ${TLINE}/translation
    INPUTTRANSLATIONFILE=${SLINE}/translation/${TRANSLATIONFILE}
    OUTPUTTRANSLATIONFILE=${TLINE}/translation/${TRANSLATIONFILE}
    
    
    REPORTFILE=${TLINE}/translate.report.md
    echo "INPUTTRANSLATIONFILE: ${INPUTTRANSLATIONFILE}" &>>${REPORTFILE}
    echo "OUTPUTTRANSLATIONFILE: ${OUTPUTTRANSLATIONFILE}" &>>${REPORTFILE}
    echo "TRANSLATIONFILE: ${TRANSLATIONFILE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}translate for language ${GOALLANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    
    if [ -f "${INPUTTRANSLATIONFILE}" ]; then
        echo "A translation file ${TRANSLATIONFILE} exists."
        echo "UPDATE the translation file: node /app/translation-json-generator.js -i ${JSONI} -t ${INPUTTRANSLATIONFILE} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${OUTPUTFILE} -p ${REPORTLINEPREFIX}"
        if ! node /app/translation-json-generator.js -i ${JSONI} -t ${INPUTTRANSLATIONFILE} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${OUTPUTTRANSLATIONFILE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
            echo "RENDER-DETAILS: failed"
            # disabled 24092025 since it caused failing translations, even when not needed
            # execution_strickness
        else
            echo "RENDER-DETAILS: translation file succesfully updated"
            pretty_print_json ${OUTPUTTRANSLATIONFILE}
        fi
    else
        echo "NO translation file ${TRANSLATIONFILE} exists"
        echo "CREATE a translation file: node /app/translation-json-generator.js -i ${JSONI} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${OUTPUTTRANSLATIONFILE} -p ${REPORTLINEPREFIX}"
        if ! node /app/translation-json-generator.js -i ${JSONI} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${OUTPUTTRANSLATIONFILE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
            echo "RENDER-DETAILS: failed"
            # disabled 24092025 since it caused failing translations, even when not needed
            # execution_strickness
        else
            echo "RENDER-DETAILS: translation file succesfully created"
            pretty_print_json ${OUTPUTTRANSLATIONFILE}
        fi
    fi
}

autotranslatefiles() {
    echo "autotranslate for primelanguage $1, goallanguage $2 and file $3 in the directory $4"
    local PRIMELANGUAGE=$1
    local GOALLANGUAGE=$2
    local JSONI=$3
    local SLINE=$4
    local TLINE=$5
    local MEMORYLINE=$6
    
    FILENAME=$(jq -r ".name" ${JSONI})
    PRIMEOUTPUTFILENAME=${FILENAME}_${PRIMELANGUAGE}.json
    GOALOUTPUTFILENAME=${FILENAME}_${GOALLANGUAGE}.json
    
    # XXX this block can be removed
    COMMANDLANGJSON=$(echo '.translation | .[] | select(.language | contains("'${GOALLANGUAGE}'")) | .translationjson')
    LANGUAGEINTHEMA=$(jq -r "${COMMANDLANGJSON}" ${JSONI})
    # secure the case that the translation file is not mentioned
    if [ "${LANGUAGEINTHEMA}" == "" ] || [ "${LANGUAGEINTHEMA}" == "null" ]; then
        TRANSLATIONFILE=${GOALOUTPUTFILENAME}
    else
        TRANSLATIONFILE=${GOALOUTPUTFILENAME}
    fi
    
    mkdir -p ${TLINE}/autotranslation
    mkdir -p ${TLINE}/translation_input
    INPUTTRANSLATIONFILE=${TLINE}/translation_input/${TRANSLATIONFILE}
    OUTPUTTRANSLATIONFILE=${TLINE}/autotranslation/${TRANSLATIONFILE}
    
    REPORTFILE=${TLINE}/autotranslate.report.md
    echo "${REPORTLINEPREFIX}autotranslate for language ${GOALLANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    
    #
    # XXX maybe also implement md5sum for the json file
    #
    #
    if [ -f ${MEMORYLINE}/${TRANSLATIONFILE} ]; then
        echo "translation memory exists on ${MEMORYLINE}."
        echo "${REPORTLINEPREFIX} update the translation file from the memory" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX}" &>>${REPORTFILE}
        
        if ! node /app/translation-json-generator.js -i ${JSONI} -t ${MEMORYLINE}/${TRANSLATIONFILE} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE}-t-${PRIMELANGUAGE} -o ${INPUTTRANSLATIONFILE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
            echo "RENDER-DETAILS: failed"
            execution_strickness
        else
            echo "RENDER-DETAILS: translation file succesfully updated"
            pretty_print_json ${OUTPUTTRANSLATIONFILE}
        fi
    else
        echo "use translation template as input for auto translation"
        cp ${TLINE}/translation/${TRANSLATIONFILE} ${INPUTTRANSLATIONFILE}
    fi
    
    if [ -f "${INPUTTRANSLATIONFILE}" ]; then
        echo "A translation file ${TRANSLATIONFILE} exists."
        # This should be revisited with autotranslation persistence at the right moment
        sed -i -e "s/${GOALLANGUAGE}-t-${PRIMELANGUAGE}/${GOALLANGUAGE}/g" ${INPUTTRANSLATIONFILE}
    fi
    
    if [ -f "${INPUTTRANSLATIONFILE}" ]; then
        echo "A translation file ${TRANSLATIONFILE} exists."
        echo "UPDATE the translation file: node /app/autotranslate.js -i ${INPUTTRANSLATIONFILE} -s ${AZURETRANSLATIONKEY} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${OUTPUTFILE} -p ${REPORTLINEPREFIX}"
        echo "${REPORTLINEPREFIX}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX} autotranslate the translation file for language ${GOALLANGUAGE}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX}" &>>${REPORTFILE}
        if ! node /app/autotranslate.js -i ${INPUTTRANSLATIONFILE} -s ${AZURETRANSLATIONKEY} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -o ${OUTPUTTRANSLATIONFILE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
            echo "RENDER-DETAILS: failed"
            execution_strickness
        else
            echo "RENDER-DETAILS: translation file succesfully updated"
            pretty_print_json ${OUTPUTTRANSLATIONFILE}
        fi
    fi
    
    # autotranslate the descriptions in the local templates
    # md5sum of the original file provides insight if a new autotranslation is needed.
    #
    pushd ${SLINE}/templates
    FILESTOPROCESS=$(find . -name "*.j2" -exec basename {} .j2 \;)
    for transi in ${FILESTOPROCESS}; do
        echo "process $transi"
        J2FILE=${transi}_${GOALLANGUAGE}.j2
        MD5SUMFILE=${transi}.j2.md5sum
        echo "${REPORTLINEPREFIX}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX} autotranslate the J2 templates for language ${GOALLANGUAGE}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX}" &>>${REPORTFILE}
        if [ -f ${MEMORYLINE}/${J2FILE} ]; then
            echo "translation memory contains ${J2FILE}"
            if [ -f ${MEMORYLINE}/$MD5SUMFILE ]; then
                CURSUM=$(md5sum ${transi}.j2)
                MEMSUM=$(cat ${MEMORYLINE}/${MD5SUMFILE})
                if [ "${CURSUM}" = "${MEMSUM}" ]; then
                    cp ${MEMORYLINE}/${J2FILE} ${TLINE}/autotranslation/${J2FILE}
                else
                    md5sum ${transi}.j2 >${TLINE}/autotranslation/${MD5SUMFILE}
                    if ! node /app/autotranslateJ2.js -i ${transi}.j2 -o ${TLINE}/autotranslation/${J2FILE} -s ${AZURETRANSLATIONKEY} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
                        echo "RENDER-DETAILS: failed"
                        execution_strickness
                    else
                        echo "RENDER-DETAILS: J2 file succesfully updated"
                    fi
                fi
            else
                md5sum ${transi}.j2 >${TLINE}/autotranslation/${MD5SUMFILE}
                if ! node /app/autotranslateJ2.js -i ${transi}.j2 -o ${TLINE}/autotranslation/${J2FILE} -s ${AZURETRANSLATIONKEY} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
                    echo "RENDER-DETAILS: failed"
                    execution_strickness
                else
                    echo "RENDER-DETAILS: J2 file succesfully updated"
                fi
            fi
        else
            md5sum ${transi}.j2 >${TLINE}/autotranslation/${MD5SUMFILE}
            if ! node /app/autotranslateJ2.js -i ${transi}.j2 -o ${TLINE}/autotranslation/${J2FILE} -s ${AZURETRANSLATIONKEY} -m ${PRIMELANGUAGE} -g ${GOALLANGUAGE} -p "${REPORTLINEPREFIX}" &>>${REPORTFILE}; then
                echo "RENDER-DETAILS: failed"
                execution_strickness
            else
                echo "RENDER-DETAILS: J2 file succesfully updated"
            fi
        fi
    done
    popd
    
    # copy the translation files to the auto translation repository for reuse in the future
    mkdir -p ${MEMORYLINE}
    cp -r ${TLINE}/autotranslation/* ${MEMORYLINE}
}

render_rdf() { # SLINE TLINE JSON
    echo "render_rdf: $1 $2 $3 $4 $5 $6 $7"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local DROOT=$5
    local RRLINE=$6
    local LANGUAGE=$7
    local PRIMELANGUAGE=${8-false}
    
    echo "DROOT: ${DROOT}"
    
    OUTPUTDIR=${TLINE}/voc
    mkdir -p ${OUTPUTDIR}
    
    FILENAME=$(jq -r ".name" ${JSONI})
    MERGEDFILENAME=merged_${FILENAME}_${LANGUAGE}.jsonld
    MERGEDFILE=${SLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    COMMANDname=$(echo '.name')
    VOCNAME=$(jq -r "${COMMANDname}" ${MERGEDFILE})
    
    COMMANDtype=$(echo '.type')
    TYPE=$(jq -r "${COMMANDtype}" ${MERGEDFILE})
    
    REPORTFILE=${RLINE}/generator-rdf.report.md
    
    # XXX TODO create an iterator for each format
    OUTPUT=${OUTPUTDIR}/${VOCNAME}_${LANGUAGE}.ttl
    OUTPUTFORMAT="text/turtle"
    
    generator_parameters rdfgenerator ${JSONI}
    
    if [ ${TYPE} == "voc" ]; then
        echo "RENDER-DETAILS(rdf): oslo-generator-rdf -s ${TYPE} -i ${MERGEDFILE} -x ${RLINE}/html-nj_${LANGUAGE}.json -r /${DROOT} -t ${TEMPLATELANG} -d ${SLINE}/templates -o ${OUTPUT} -m ${LANGUAGE} -e ${RRLINE}"
        
        case $TYPE in
            ap)
                SPECTYPE="ApplicationProfile"
            ;;
            voc)
                SPECTYPE="Vocabulary"
            ;;
            oj)
                SPECTYPE="ApplicationProfile"
            ;;
            *)
                echo "ERROR: ${SPECTYPE} not recognized"
                SPECTYPE="ApplicationProfile"
            ;;
        esac
        
        echo "${REPORTLINEPREFIX}oslo-generator-rdf for language ${LANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
        oslo-generator-rdf \
        --input ${MERGEDFILE} \
        --output ${OUTPUT} \
        --contentType ${OUTPUTFORMAT} \
        --silent false \
        --language ${LANGUAGE} \
        ${PARAMETERS} \
        &>>${REPORTFILE}
        
        if [ $? -gt 0 ]; then
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        if [ -f ${OUTPUT} ]; then
            echo "RENDER-DETAILs: success"
        else
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        
        if [ ${PRIMELANGUAGE} == true ]; then
            cp ${OUTPUT} ${OUTPUTDIR}/${VOCNAME}.ttl
        fi
        echo "RENDER-DETAILS(RDF): File was rendered in ${OUTPUT}"
    fi
    
}

render_nunjunks_html() { # SLINE TLINE JSON
    echo "render_html: $1 $2 $3 $4 $5 $6 $7"
    echo "render_html: $1 $2 $3 $4 $5"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local DROOT=$5
    local RRLINE=$6
    local LANGUAGE=$7
    local PRIMELANGUAGE=${8-false}
    
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    
    case $TYPE in
        ap)
            SPECTYPE="ApplicationProfile"
        ;;
        voc)
            SPECTYPE="Vocabulary"
        ;;
        oj)
            SPECTYPE="ApplicationProfile"
        ;;
        *)
            echo "ERROR: ${SPECTYPE} not recognized"
            SPECTYPE="ApplicationProfile"
        ;;
    esac
    
    echo "Creating a webuniversum config for a ${TYPE}"
    
    FILENAME=$(jq -r ".name" ${JSONI})
    MERGEDFILENAME=merged_${FILENAME}_${LANGUAGE}.jsonld
    MERGEDFILE=${RRLINE}/merged/${MERGEDFILENAME} # XXX This should be the source of the translation merged files
    
    if [ -f "${MERGEDFILE}" ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    # step 1: extract all information for a html representation
    
    mkdir -p ${RLINE}/html
    INT_OUTPUT=${RLINE}/html/int_${FILENAME}_${LANGUAGE}.json
    INT_REPORTFILE=${RLINE}/generator-webuniversum-json.report.md
    
    generator_parameters webuniversumgenerator ${JSONI}
    
    echo "${REPORTLINEPREFIX}oslo-webuniversum-json-generator for language ${LANGUAGE}${REPORTLINENEWLINE}" &>>${INT_REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${INT_REPORTFILE}
    oslo-webuniversum-json-generator \
    --input ${MERGEDFILE} \
    --output ${INT_OUTPUT} \
    --specificationType ${SPECTYPE} \
    --language ${LANGUAGE} \
    --publicationEnvironment $HOSTNAME \
    ${PARAMETERS} \
    &>>${INT_REPORTFILE}
    
    if [ $? -gt 0 ]; then
        echo "RENDER-DETAILS: failed"
        cat ${INT_REPORTFILE}
        execution_strickness
    fi
    
    # step 2: create the html
    
    generator_parameters htmlgenerator ${JSONI}
    
    # precendence order: Theme repository > publication repository > tool repository
    # the tool installed templates are located at /usr/local/lib/node_modules/@oslo-flanders/html-generator/lib/templates
    mkdir -p ${RRLINE}/templates
    cp -n ${SLINE}/templates/* ${RRLINE}/templates
    cp -n ${RRLINE}/autotranslation/*.j2 ${RRLINE}/templates
    cp -n ${HOME}/project/templates/* ${RRLINE}/templates
    #cp -n /app/views/* ${SLINE}/templates
    #cp -n ${HOME}/project/templates/icons/* ${SLINE}/templates/icons
    mkdir -p ${RLINE}
    
    OUTPUT=${TLINE}/index_${LANGUAGE}.html
    COMMANDTEMPLATELANG=$(echo '.translation | .[] | select(.language | contains("'${LANGUAGE}'")) | .template')
    TEMPLATELANG=$(jq -r "${COMMANDTEMPLATELANG}" ${JSONI})
    # in case of autotranslate all translations should exists
    COMMANDTITLELANG=$(echo '.translation | .[] | select(.title | contains("'${LANGUAGE}'")) | .template')
    TITLELANG=$(jq -r "${COMMANDTITLELANG}" ${JSONI})
    
    REPORTFILE=${RLINE}/generator-html.report.md
    
    METADATA=${RRLINE}/html/meta_${FILENAME}_${LANGUAGE}.json
    STAKEHOLDERS=${RRLINE}/stakeholders.json
    
    echo "${REPORTLINEPREFIX}oslo-generator-html for language ${LANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    oslo-generator-html \
    --input ${INT_OUTPUT} \
    --output ${OUTPUT} \
    --stakeholders ${STAKEHOLDERS} \
    --metadata ${METADATA} \
    --specificationType ${SPECTYPE} \
    --specificationName ${TITLELANG} \
    --templates ${RRLINE}/templates \
    --rootTemplate ${TEMPLATELANG} \
    --silent false \
    --language ${LANGUAGE} \
    ${PARAMETERS} \
    &>>${REPORTFILE}
    
    if [ $? -gt 0 ]; then
        echo "RENDER-DETAILS: failed"
        cat ${REPORTFILE}
        execution_strickness
    fi
    if [ -f ${OUTPUT} ]; then
        echo "RENDER-DETAILs: success"
    else
        echo "RENDER-DETAILS: failed"
        cat ${REPORTFILE}
        execution_strickness
    fi
    
    if [ ${PRIMELANGUAGE} == true ]; then
        cp ${OUTPUT} ${TLINE}/index.html
    fi
    echo "RENDER-DETAILS(language html): File was rendered in ${OUTPUT}"
}

render_respec_html() { # SLINE TLINE JSON
    echo "render_html: $1 $2 $3 $4 $5 $6 $7"
    echo "render_html: $1 $2 $3 $4 $5"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local DROOT=$5
    local RRLINE=$6
    local LANGUAGE=$7
    local PRIMELANGUAGE=${8-false}
    
    FILENAME=$(jq -r ".name" ${JSONI})
    MERGEDFILENAME=merged_${FILENAME}_${LANGUAGE}.jsonld
    MERGEDFILE=${RRLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    # precendence order: Theme repository > publication repository > tool repository
    # XXX TODO: reactivate
    #cp -n ${HOME}/project/templates/* ${SLINE}/templates
    #cp -n /app/views/* ${SLINE}/templates
    #cp -n ${HOME}/project/templates/icons/* ${SLINE}/templates/icons
    mkdir -p ${RLINE}
    
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    
    mkdir -p ${TLINE}/html
    
    OUTPUT=${TLINE}/respec-index_${LANGUAGE}.html
    COMMANDTEMPLATELANG=$(echo '.translation | .[] | select(.language | contains("'${LANGUAGE}'")) | .template')
    TEMPLATELANG=$(jq -r "${COMMANDTEMPLATELANG}" ${JSONI})
    # in case of autotranslate all translations should exists
    COMMANDTITLELANG=$(echo '.translation | .[] | select(.title | contains("'${LANGUAGE}'")) | .template')
    TITLELANG=$(jq -r "${COMMANDTITLELANG}" ${JSONI})
    
    REPORTFILE=${RLINE}/generator-respec.report.md
    generator_parameters respecgenerator ${JSONI}
    
    case $TYPE in
        ap)
            SPECTYPE="ApplicationProfile"
        ;;
        voc)
            SPECTYPE="Vocabulary"
        ;;
        oj)
            SPECTYPE="ApplicationProfile"
        ;;
        *)
            echo "ERROR: ${SPECTYPE} not recognized"
            SPECTYPE="ApplicationProfile"
        ;;
    esac
    
    echo "${REPORTLINEPREFIX}oslo-generator-respec for language ${LANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
    echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
    oslo-generator-respec \
    --input ${MERGEDFILE} \
    --output ${OUTPUT} \
    --specificationType ${SPECTYPE} \
    --specificationName ${TITLELANG} \
    --silent false \
    --language ${LANGUAGE} \
    ${PARAMETERS} \
    &>>${REPORTFILE}
    
    if [ $? -gt 0 ]; then
        echo "RENDER-DETAILS: failed"
        cat ${REPORTFILE}
        execution_strickness
    fi
    
}

link_html() { # SLINE TLINE JSON
    echo "link_html: $1 $2 $3 $4 $5 $6 $7"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local DROOT=$5
    local RRLINE=$6
    local LANGUAGE=$7
    
}

function pretty_print_json() {
    # echo "pretty_print_json: $1"
    if [ -f "$1" ]; then
        jq . $1 >/tmp/pp.json
        mv /tmp/pp.json $1
    fi
}

render_example_template() { # SLINE TLINE JSON
    echo "render_example_template: $1 $2 $3 $4 $5 $6 $7"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local DROOT=$5
    local RRLINE=$6
    local LANGUAGE=$7
    
    echo "XXX TODO This option is not yet implemented as a solution in version 4"
    
    FILENAME=$(jq -r ".name" ${JSONI})
    MERGEDFILENAME=merged_${FILENAME}_${LANGUAGE}.jsonld
    MERGEDFILE=${RLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    OUTPUT=${TLINE}/examples/
    mkdir -p ${OUTPUT}
    mkdir -p ${OUTPUT}/context
    touch ${OUTPUT}/.gitignore
    
    COMMAND=$(echo '.examples')
    EXAMPLE=$(jq -r "${COMMAND}" ${MERGEDFILE})
    echo "example " ${EXAMPLE}
    if [ "${EXAMPLE}" == true ]; then
        echo "no generator execution defined"
        #        echo "RENDER-DETAILS(example generator): node /app/exampletemplate-generator2.js -i ${MERGEDJSONLD} -o ${OUTPUT} -l ${LANGUAGE} -h /doc/${TYPE}/${BASENAME}"
        #        if ! node /app/exampletemplate-generator2.js -i ${MERGEDJSONLD} -o ${OUTPUT} -l ${LANGUAGE} -h /doc/${TYPE}/${BASENAME}; then
        #            echo "RENDER-DETAILS(example generator): rendering failed"
        #            execution_strickness
        #        else
        #            echo "RENDER-DETAILS(example generator): Files were rendered in ${OUTPUT}"
        #        fi
    fi
}

touch2() { mkdir -p "$(dirname "$1")" && touch "$1"; }

prettyprint_jsonld() {
    local FILE=$1
    
    if [ -f ${FILE} ]; then
        touch2 /tmp/pp/${FILE}
        jq --sort-keys . ${FILE} >/tmp/pp/${FILE}
        cp /tmp/pp/${FILE} ${FILE}
    fi
}

render_context() { # SLINE TLINE JSON
    echo "render_context: $1 $2 $3 $4 $5"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local GOALLANGUAGE=$5
    local PRIMELANGUAGE=${6-false}
    
    FILENAME=$(jq -r ".name" ${JSONI})
    OUTFILE=${FILENAME}.jsonld
    OUTFILELANGUAGE=${FILENAME}_${GOALLANGUAGE}.jsonld
    
    MERGEDFILENAME=merged_${FILENAME}_${GOALLANGUAGE}.jsonld
    MERGEDFILE=${SLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    REPORTFILE=${RLINE}/generator-jsonld-context.report.md
    mkdir -p ${RLINE}
    
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    OUTPUT=${TLINE}/context/${OUTFILELANGUAGE}
    
    case $TYPE in
        ap)
            SPECTYPE="ApplicationProfile"
        ;;
        voc)
            SPECTYPE="Vocabulary"
        ;;
        oj)
            SPECTYPE="ApplicationProfile"
        ;;
        *)
            echo "ERROR: ${SPECTYPE} not recognized"
            SPECTYPE="ApplicationProfile"
        ;;
    esac
    
    generator_parameters contextgenerator ${JSONI}
    
    if [ ${SPECTYPE} == "ApplicationProfile" ]; then
        mkdir -p ${TLINE}/context
        
        echo "${REPORTLINEPREFIX}oslo-jsonld-context-generator for language ${GOALLANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
        oslo-jsonld-context-generator \
        --input ${MERGEDFILE} \
        --language ${GOALLANGUAGE} \
        --output ${OUTPUT} \
        ${PARAMETERS} \
        &>>${REPORTFILE}
        
        if [ $? -gt 0 ]; then
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        if [ -f ${OUTPUT} ]; then
            echo "RENDER-DETAILs: success"
        else
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        
        prettyprint_jsonld ${TLINE}/context/${OUTFILELANGUAGE}
        if [ ${PRIMELANGUAGE} == true ]; then
            cp ${TLINE}/context/${OUTFILELANGUAGE} ${TLINE}/context/${OUTFILE}
        fi
    fi
}


render_swagger() {
    echo "render_swagger: $1 $2 $3 $4 $5"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local DROOT=$5
    local GOALLANGUAGE=$6
    local PRIMELANGUAGE=${7-false}
    
    FILENAME=$(jq -r ".name" ${JSONI})
    OUTFILE=${FILENAME}.yaml
    OUTFILELANGUAGE=${FILENAME}_${GOALLANGUAGE}.yaml
    
    MERGEDFILENAME=merged_${FILENAME}_${GOALLANGUAGE}.jsonld
    MERGEDFILE=${SLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    REPORTFILE=${RLINE}/generator-swagger.report.md
    mkdir -p ${RLINE}
    
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    echo $TYPE
    echo "render_swagger: $1 $2 $3 $4 $5"
    
    
    case $TYPE in
        ap)
            SPECTYPE="ApplicationProfile"
        ;;
        voc)
            SPECTYPE="Vocabulary"
        ;;
        oj)
            SPECTYPE="ApplicationProfile"
        ;;
        *)
            echo "ERROR: ${SPECTYPE} not recognized"
            SPECTYPE="ApplicationProfile"
        ;;
    esac
    
    OUTPUT=${TLINE}/swagger/${OUTFILELANGUAGE}
    
    generator_parameters swaggergenerator ${JSONI}
    
    if [ ${SPECTYPE} == "ApplicationProfile" ]; then
        mkdir -p ${TLINE}/swagger
        
        # Construct the context URL dynamically
        CONTEXT_URL="${HOSTNAME}/${DROOT}/context/${FILENAME}.jsonld"
        
        echo "${REPORTLINEPREFIX} oslo-generator-swagger for language ${GOALLANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX} -------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
        oslo-generator-swagger \
        --input ${MERGEDFILE} \
        --language ${GOALLANGUAGE} \
        --output ${OUTPUT} \
        --versionAPI 1.0.0 \
        --versionSwagger 3.0.4 \
        --title "OpenAPI Swagger publication" \
        --description "This is a inspirational OpenAPI Swagger publication" \
        --contextURL ${CONTEXT_URL} \
        --baseURL ${HOSTNAME} \
        ${PARAMETERS} \
        &>>${REPORTFILE}
        
        if [ $? -gt 0 ]; then
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        if [ -f ${OUTPUT} ]; then
            echo "RENDER-DETAILs: success"
        else
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        
        prettyprint_jsonld ${TLINE}/swagger/${OUTFILELANGUAGE}
        if [ ${PRIMELANGUAGE} == true ]; then
            cp ${TLINE}/swagger/${OUTFILELANGUAGE} ${TLINE}/swagger/${OUTFILE}
        fi
    fi
}


render_shacl_languageaware() {
    echo "render_shacl: $1 $2 $3 $4 $5"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local LINE=$5
    local GOALLANGUAGE=$6
    local PRIMELANGUAGE=${7-false}
    
    FILENAME=$(jq -r ".name" ${JSONI})
    
    MERGEDFILENAME=merged_${FILENAME}_${GOALLANGUAGE}.jsonld
    MERGEDFILE=${SLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    OUTFILE=${TLINE}/shacl/${FILENAME}-SHACL_${GOALLANGUAGE}.jsonld
    OUTREPORT=${RLINE}/shacl/${FILENAME}-SHACL_${GOALLANGUAGE}.report.md
    
    REPORTFILE=${RLINE}/generator-shacl.report.md
    
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    
    echo "$TYPE"
    
    case $TYPE in
        ap)
            SPECTYPE="ApplicationProfile"
        ;;
        voc)
            SPECTYPE="Vocabulary"
        ;;
        oj)
            SPECTYPE="ApplicationProfile"
        ;;
        *)
            echo "ERROR: ${SPECTYPE} not recognized"
            SPECTYPE="ApplicationProfile"
        ;;
    esac
    echo "$SPECTYPE"
    
    generator_parameters shaclgenerator ${JSONI}
    
    if [ ${SPECTYPE} == "ApplicationProfile" ]; then
        
        HH=$(echo ${HOSTNAME} | sed -e "s|/$||g")
        LL=$(echo ${LINE} | sed -e "s|^/||g")
        
        SHAPEBASEURI="${HH}/${LL}#"
        DOCUMENTURL="${HH}/${LL}"
        mkdir -p ${TLINE}/shacl
        mkdir -p ${RLINE}/shacl
        
        echo "${REPORTLINEPREFIX}oslo-shacl-template-generator for language ${GOALLANGUAGE}${REPORTLINENEWLINE}" &>>${REPORTFILE}
        echo "${REPORTLINEPREFIX}-------------------------------------${REPORTLINENEWLINE}" &>>${REPORTFILE}
        oslo-shacl-template-generator \
        --input ${MERGEDFILE} \
        --language ${GOALLANGUAGE} \
        --output ${OUTFILE} \
        --shapeBaseURI ${SHAPEBASEURI} \
        --applicationProfileURL ${DOCUMENTURL} \
        ${PARAMETERS} \
        &>>${REPORTFILE}
        
        if [ $? -gt 0 ]; then
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        if [ -f ${OUTFILE} ]; then
            echo "RENDER-DETAILs: success"
        else
            echo "RENDER-DETAILS: failed"
            cat ${REPORTFILE}
            execution_strickness
        fi
        
        prettyprint_jsonld ${OUTFILE}
        if [ ${PRIMELANGUAGE} == true ]; then
            cp ${OUTFILE} ${TLINE}/shacl/${FILENAME}-SHACL.jsonld
        fi
    fi
    #    fi
}

render_xsd() { # SLINE TLINE JSON
    echo "render_xsd: $1 $2 $3 $4 $5"
    local SLINE=$1
    local TLINE=$2
    local JSONI=$3
    local RLINE=$4
    local GOALLANGUAGE=$5
    local PRIMELANGUAGE=${6-false}
    
    echo "XXX TODO This option is not yet implemented as a solution in version 4"
    
    FILENAME=$(jq -r ".name" ${JSONI})
    MERGEDFILENAME=merged_${FILENAME}_${GOALLANGUAGE}.jsonld
    MERGEDFILE=${RLINE}/merged/${MERGEDFILENAME}
    
    if [ -f ${MERGEDFILE} ]; then
        echo "translations integrated file found"
    else
        echo "defaulting to the primelanguage version"
        MERGEDFILE=${JSONI}
    fi
    
    OUTFILE=${FILENAME}.xsd
    OUTFILELANGUAGE=${FILENAME}_${GOALLANGUAGE}.xsd
    
    mkdir -p ${TLINE}/xsd
    touch ${TLINE}/xsd/.gitignore
    
    COMMAND=$(echo '.type')
    TYPE=$(jq -r "${COMMAND}" ${JSONI})
    
    #    XSDDOMAIN="https://data.europa.eu/m8g/xml/"
    
    if [ ${TYPE} == "ap" ] || [ ${TYPE} == "oj" ]; then
        
        #        echo "RENDER-DETAILS(xsd): node /app/xsd-generator.js -d -l label -i ${MERGEDJSONLD} -o ${TLINE}/xsd/${OUTFILELANGUAGE} -m ${GOALLANGUAGE} -b ${XSDDOMAIN}"
        #        if ! node /app/xsd-generator.js -d -l label -i ${MERGEDJSONLD} -o ${TLINE}/xsd/${OUTFILELANGUAGE} -m ${GOALLANGUAGE} -b ${XSDDOMAIN}; then
        #            echo "RENDER-DETAILS(xsd): See XXX for more details, Rendering failed"
        #            execution_strickness
        #        else
        #            echo "RENDER-DETAILS(xsd): Rendering successfull, File saved to  ${TLINE}/xsd/${OUTFILELANGUAGE}"
        #        fi
        
        if [ ${PRIMELANGUAGE} == true ]; then
            cp ${TLINE}/xsd/${OUTFILELANGUAGE} ${TLINE}/xsd/${OUTFILE}
        fi
        
    fi
}

echo "render-details: starting with $1 $2 $3"

BUNDLING_EXECUTED=false

cat ${CHECKOUTFILE} | while read line; do
    SLINE=${TARGETDIR}/src/${line}
    TLINE=${TARGETDIR}/report4/${line}
    RLINE=${TARGETDIR}/report4/${line}
    TRLINE=${TARGETDIR}/translation/${line}
    echo "RENDER-DETAILS: Processing line ${SLINE} => ${TLINE},${RLINE}"
    #
    # TODO: the extract-what-4.sh writes the derived output in TLINE/RLINE
    # In 3.0 version this was in the SLINE
    # Therefore the next test should be considered in redesign of extract-what-4
    if [ -d "${RLINE}" ]; then
        for i in ${RLINE}/all-*.jsonld; do
            echo "RENDER-DETAILS: convert $i using ${DETAILS}"
            case ${DETAILS} in
                html)
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/html/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    render_nunjunks_html $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report4/${line} ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_nunjunks_html $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report4/${line} ${g}
                        fi
                    done
                ;;
                respec)
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/respec/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    render_respec_html $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report4/${line} ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_respec_html $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report4/${line} ${g}
                        fi
                    done
                ;;
                rdf)
                    # the source for the shacl generator is solely the intermediate json
                    SLINE=${TARGETDIR}/report4/${line}
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/rdf/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    render_rdf $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report4/${line} ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_rdf $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report4/${line} ${g}
                        fi
                    done
                ;;
                shacl)
                    # the source for the shacl generator is solely the intermediate json
                    SLINE=${TARGETDIR}/report4/${line}
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/shacl/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    render_shacl_languageaware $SLINE $TLINE $i $RLINE ${line} ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_shacl_languageaware $SLINE $TLINE $i $RLINE ${line} ${g}
                        fi
                    done
                    NAMESPEC=FIRST_PART=$(echo "$MY_PATH" | cut -d'/' -f3)
                    #node /app/update-shacl-report.js -i ${RLINE}/generator-shacl.report.md -o ${RLINE}/generator-shacl.report.md -l https://github.com/Informatievlaanderen/data.vlaanderen.be2-generated/blob/dev4.0/report4/doc/${line}/all-${NAMESPEC}-ap.jsonld -a ${TARGETDIR}/report4/doc/${line}/all-${NAMESPEC}-ap.jsonld
                    #                node /app/update-shacl-report.js -i ${RLINE}/generator-shacl.report.md -o ${RLINE}/generator-shacl.report.md -l $i -a $i
                    #                move this in the report handling
                ;;
                context)
                    # the source for the context generator is solely the intermediate json
                    SLINE=${TARGETDIR}/report4/${line}
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/context/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    render_context $SLINE $TLINE $i $RLINE ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_context $SLINE $TLINE $i $RLINE ${g}
                        fi
                    done
                ;;
                swagger)
                    # the source for the swagger generator is solely the intermediate json
                    SLINE=${TARGETDIR}/report4/${line}
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/swagger/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    render_swagger $SLINE $TLINE $i $RLINE ${line} ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_swagger $SLINE $TLINE $i $RLINE ${line} ${g}
                        fi
                    done
                ;;
                validation)
                    # the source for the jsonld validator is solely the intermediate json
                    echo "RENDER-DETAILS: validation"
                    echo ${line}
                    SLINE=${TARGETDIR}/report4/${line}
                    TLINE=${TARGETDIR}/target/${line}
                    RLINE=${TARGETDIR}/report4/jsonld-validation/${line}
                    mkdir -p ${TLINE}
                    mkdir -p ${RLINE}
                    validate_jsonld $SLINE $TLINE $i $RLINE ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            validate_jsonld $SLINE $TLINE $i $RLINE ${PRIMELANGUAGE} true
                        fi
                    done
                ;;
                xsd)
                    render_xsd $SLINE $TLINE $i $RLINE ${PRIMELANGUAGE} true
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_xsd $SLINE $TLINE $i $RLINE ${g}
                        fi
                    done
                ;;
                metadata)
                    render_metadata ${PRIMELANGUAGE} $i ${line} ${SLINE} ${TLINE}
                    for g in ${GOALLANGUAGE}; do
                        render_metadata ${g} $i ${line} ${SLINE} ${TLINE}
                    done
                ;;
                translation)
                    render_translationfiles ${PRIMELANGUAGE} ${PRIMELANGUAGE} $i ${SLINE} ${TLINE}
                    for g in ${GOALLANGUAGE}; do
                        render_translationfiles ${PRIMELANGUAGE} ${g} $i ${SLINE} ${TLINE}
                    done
                ;;
                autotranslate)
                    AUTOTRANSLATE=$(jq -r .toolchain.autotranslate ${CONFIGDIR}/config.json)
                    if [ ${AUTOTRANSLATE} == true ]; then
                        for g in ${GOALLANGUAGE}; do
                            autotranslatefiles ${PRIMELANGUAGE} ${g} $i ${SLINE} ${TLINE} ${AUTOTRANSLATIONDIR}/${line}
                        done
                    fi
                ;;
                merge)
                    render_merged_files ${PRIMELANGUAGE} ${PRIMELANGUAGE} $i ${SLINE} ${TLINE} ${RLINE}
                    for g in ${GOALLANGUAGE}; do
                        render_merged_files ${PRIMELANGUAGE} ${g} $i ${SLINE} ${TLINE} ${RLINE}
                    done
                ;;
                bundle)
                    if [ "${BUNDLING_EXECUTED}" != "true" ]; then
                        echo "RENDER-DETAILS: bundling resources"
                        if ! ${PWD}/scripts/copy_resources_to_urlref.sh ${CONFIGDIR} ${TARGETDIR}/target ${TARGETDIR}; then
                            echo "RENDER-DETAILS: bundling failed"
                            execution_strickness
                        fi
                        BUNDLING_EXECUTED=true
                    fi
                ;;
                report)
                    EXECUTIONVIEW=${TARGETDIR}/report4/overviewreport.md
                    OLD_GLOBAL_OVERVIEW=${TARGETDIR}/README.md
                    GLOBAL_OVERVIEW=${TARGETDIR}/report4/README.md
                    render_report_line ${line} ${RLINE} $i ${EXECUTIONVIEW} ${OLD_GLOBAL_OVERVIEW} ${GLOBAL_OVERVIEW}
                ;;
                example)
                    render_example_template $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report/${line} ${PRIMELANGUAGE}
                    for g in ${GOALLANGUAGE}; do
                        generate_for_language ${g} ${i}
                        if [ ${GENERATEDARTEFACT} == true ]; then
                            render_example_template $SLINE $TLINE $i $RLINE ${line} ${TARGETDIR}/report/${line} ${g}
                        fi
                    done
                ;;
                *) echo "RENDER-DETAILS: ${DETAILS} not handled yet" ;;
            esac
        done
    else
        echo "Error: ${SLINE}"
    fi
done
