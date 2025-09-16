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