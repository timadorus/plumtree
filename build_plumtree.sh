#!/bin/bash -ev
#
# run build and test (unit and integration)
#

PROJECT="plumtree"
BASEDIR=`realpath $( dirname $0 )`
WORKDIR=`pwd`
COMMAND=$1

function agent_notice {
    cat <<-EOF

This script requires that you have a ssh-agent running, and have loaded the
required key(s) to
   a) access all git repositories listed in the sources code dependencies
   b) can connect to the test machine(s) without the need for further input of
      authentication information.

EOF
}

function check_agent {
    agent_line=`ssh-add -l 2>&1`

    case "${agent_line}" in
        [0-9][0-9][0-9][0-9]\ [[:alnum:]]*)
#           echo "have key: $agent_line"
        ;;
        "The agent has no identities.")
            echo
            echo "Have reached ssh-agent, the agent has no id's loaded."

            agent_notice
            exit -1
        ;;
        "Could not open a connection to your authentication agent.")
            echo
            echo "Could not contact agent"

            agent_notice
            exit -1
        ;;
    esac
}


#########################################
#      PRE FLIGHT CHECKS                #
#########################################
function flight_checks {
    # do we have a loaded agent running?
    check_agent

    # check that more than one CPU is present, otherwise race conditions have it too easy to slip by.
    cpu_count=`cat /proc/cpuinfo | grep '^processor' | wc -l`
    if [ $cpu_count -lt 2 ]
     then
       echo "test environment requires at least 2 cpus to catch a number of race conditions."
       echo "Only ${cpu_count} cpus detected, terminating"
       exit -1
     fi
}


#########################################
#          PULL CHANGES IN SOURCE       #
#########################################
function pull_source {

    for dir in src test c_src steps include features
     do
      # remove existing project source files
      rm -rf "${WORKDIR}/${PROJECT}_local/${dir}"

      # copy src and test files to work dir
      if [ -d "${BASEDIR}/${dir}" ]
        then
          cp -a "${BASEDIR}/${dir}" "${WORKDIR}/${PROJECT}_local/"
        else
          echo "Warning: directory ${BASEDIR}/${dir} not found in project. Directory is listed as standard project dir."
        fi
     done

    for file in rebar.config rebar.config.script elvis.config dialyzer.ignore-warning
      do
        if [ -f "${BASEDIR}/${file}" ]
          then
            cp -a "${BASEDIR}/${file}" "${WORKDIR}/${PROJECT}_local/"
          else
            echo "Warning: file ${BASEDIR}/${file} not found in project. File is listed as standard project file."
          fi
      done
}


#########################################
#      UPDATE CODE and REBUILD          #
#########################################
function update {

    pushd "${WORKDIR}/${PROJECT}_local"

    pull_source

    rebar3 eunit
    rebar3 cover
    rebar3 as test dialyzer

}

#########################################
#      START BUILD                      #
#########################################
function build {

    if [ -d "${WORKDIR}/${PROJECT}_local" ]
     then
      rm -rf "${WORKDIR}/${PROJECT}_local"
     fi

    cp -a "${BASEDIR}" "${WORKDIR}/${PROJECT}_local"

    # ensure that nginx can read the build data
    chmod a+rx "${WORKDIR}/${PROJECT}_local"

    pushd "${WORKDIR}/${PROJECT}_local"

    # remove eclipse fluff
    rm -f ebin/*.beam "ebin/${PROJECT}.app"

    rebar3 deps
    rebar3 eunit
    rebar3 cover
    rebar3 as test dialyzer

    rebar3 as prod compile
    rebar3 as prod release tar

}


#########################################
#      START DEBUGGER                   #
#########################################

function debug {
    export ERL_LIBS="${WORKDIR}/${PROJECT}_local/_build/test/lib"

    pushd "${WORKDIR}/${PROJECT}_local/_build/test/lib/quperl_client"
    erl -pa "${WORKDIR}/${PROJECT}_local/_build/test/lib/quperl_client/test"
    popd
}


flight_checks

case $COMMAND in
    build )
        echo "...building...."
        build
        exit 0
    ;;
    update )
        echo "...updating...."
        update
        exit 0
    ;;
    debug )
        echo "...starting debugger...."
        debug
esac

