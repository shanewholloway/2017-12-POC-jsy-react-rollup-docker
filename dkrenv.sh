#!/bin/bash

function cmd_create {
  cmd_build
  SVC_ARGS=$(node ./tools/svc_args.js)
  docker service create --detach=false $SVC_ARGS --name=$DKRENV_SVC $DKRENV_IMG
}
function cmd_update {
  cmd_build
  docker service update --detach=false \
    --image $DKRENV_IMG:latest \
    $DKRENV_SVC
}
function cmd_start {
  if ! is_running ; then
    cmd_create ;
  else
    cmd_update ;
  fi
}
function cmd_stop {
  docker service rm $DKRENV_SVC 2&> /dev/null
}
function is_running {
  if [ -z ${SVC_IDS+x} ] ; then
    SVC_IDS=($(docker service ls -q --filter "name=$DKRENV_SVC"))
  fi
  return $(( 0 == ${#SVC_IDS[@]} ))
}


function cmd_exec {
  DKR_IDS=($(docker ps -q --filter "label=com.docker.swarm.service.name=$DKRENV_SVC"))
  docker exec -it $DKR_IDS bash
}
function cmd_logs {
  docker service logs $DKRENV_SVC --follow
}



function dkr_build {
  ##if [[ -z ${BRIDGE_IP+x} ]] ; then
    ## NPMRC=$(cat ~/.npmrc)
    ## e.g. `docker build --build-arg NPMRC="$NPMRC" ...
    ## BRIDGE_IP=$(docker network inspect 'bridge' --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
    ## e.g. `docker build --add-host sr-npm-registry:$BRIDGE_IP` ...
  ##fi
  docker build $*
}

function cmd_build {
  if [[ -n ${CI_SERVER+x} ]] ; then
    # On GitLab-like build server; skip DKRENV tooling
    echo "In CI/CD Build Environment"

    # Use the primary Dockerfile build target to create $DKRENV_IMG:latest
    dkr_build -f $DKRENV_DKRFILE -t $DKRENV_IMG:latest .

  else
    echo "In Local Development Environment"

    # Use the primary Dockerfile build target to create $DKRENV_IMG:build
    dkr_build --target build -f $DKRENV_DKRFILE -t $DKRENV_IMG:build .

    # Use the primary Dockerfile build target to create $DKRENV_IMG:latest
    dkr_build -f $DKRENV_DKRFILE -t $DKRENV_IMG:latest .

    docker push $DKRENV_IMG:latest
  fi
}

function cmd_build_devel {
  # Add any localized devel overrides to the build image, creating $DKRENV_IMG:devel
  dkr_build -f ./Dockerfile.devel --build-arg DKRENV_IMG=$DKRENV_IMG -t $DKRENV_IMG:devel .
}

function cmd_watch {
  if ! is_running ; then cmd_create ; fi

  cmd_build_devel

  docker service update --detach=false \
    --mount-add type=bind,dst=/usr/src/app/dist/public,src=$PWD/approot/dist/public \
    $DKRENV_SVC

  # Watch for dist changes; upon change run the live entrypoint of this script
  npx nodemon --signal SIGTERM --no-stdin --delay 1 \
    --watch ./approot/dist \
    --ignore ./approot/dist/public \
    --watch ./approot/deps/*/dist \
    --exec "bash $0 live"
}

function cmd_live {
  # Apply changes atop the $DKRENV_IMG:devel to create the new $DKRENV_IMG:live
  dkr_build -f ./Dockerfile.live --build-arg DKRENV_IMG=$DKRENV_IMG -t $DKRENV_IMG:live .

  # Update the service to use $DKRENV_IMG:live
  docker push $DKRENV_IMG:live
  docker service update --detach=false \
    --image $DKRENV_IMG:live \
    $DKRENV_SVC
}

function cmd_ls {
  docker image ls $DKRENV_IMG
}
function cmd_clean {
  echo
  if is_running ; then 
    IMGS=($( docker image ls --format '{{ if eq .Tag "\u003cnone\u003e" }} {{.ID}} {{end}}' $DKRENV_IMG ))
  else
    IMGS=($( docker image ls --format '{{ if ne .Tag "\u003cnone\u003e" }} {{.Repository}}:{{.Tag}} {{else}} {{.ID}} {{end}}' $DKRENV_IMG ))
  fi

  if [[ 0 < ${#IMGS[@]} ]] ; then
    echo "Cleaning ${#IMGS[@]} images of '$DKRENV_IMG'"
    docker image rm ${IMGS[@]}
  else
    echo "Zero images of '$DKRENV_IMG' to clean (${#IMGS[@]})"
  fi
  echo
}


if [[ -n "$npm_package_dkrenv_svc" ]] ; then export DKRENV_SVC=$npm_package_dkrenv_svc ; fi
if [[ -n "$npm_package_dkrenv_img" ]] ; then export DKRENV_IMG=$npm_package_dkrenv_img ; fi
if [[ -n "$npm_package_dkrenv_dockerfile" ]] ; then export DKRENV_DKRFILE=$npm_package_dkrenv_dockerfile ; fi
if [[ -z "$DKRENV_SVC" || -z "$DKRENV_IMG" ]] ; then exec npm -s run :dkrenv -- $1; fi
if [[ -z "$DKRENV_DKRFILE" ]] ; then export DKRENV_DKRFILE=./Dockerfile ; fi

trap "exit 1;" SIGINT

case "$1" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  create) cmd_create ;;
  update) cmd_update ;;

  logs) cmd_logs ;;
  exec) cmd_exec ;;

  build) cmd_build ;;
  devel) cmd_build_devel ;;
  watch) cmd_watch ;;
  live) cmd_live ;;

  ls) cmd_ls ;;
  clean) cmd_clean ;;

  *)
    echo $"Usage: $0 {start|stop|update|build|watch|logs|exec}"
    exit 1 ;;
esac ;

exit 0

