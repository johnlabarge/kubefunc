#!/usr/bin/env bash
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


HELP="Create interactive pod for debugging data in NFS mounts\n\n\
  Run an interactive pod in the cluster for debugging purposes.\n\
  Pod is removed when shell exists.\n\
  Image is 'debian:latest'\n\
  First argument is the SERVER:PATH for the NFS mount.\n\
  If no arguments are given, you will be prompted for the SERVER:PATH.\n\
  Example:\n
    kubectl nfsshell\n
    kubectl nfsshell 10.0.0.2:/data
"
if [[ "$1" == "help" || "$1" == "-h" ]]
then
  echo -e $HELP
  exit 0
fi

export POD_NAME=""
function cleanup() {
    [[ -n "${POD_NAME}" ]] && kubectl delete pod ${POD_NAME} >/dev/null 2>&1 || true
}
trap cleanup EXIT TERM

function _get_nfs_info() {
    serverpath=""
    while [[ -z "${serverpath}" ]]; do
        read -p "Enter path to NFS mount in the form of SERVER:PATH : " input >&2
        IFS=':' read -ra toks <<< "${input}"
        if [[ ${#toks[@]} -ne 2 ]]; then
          echo "Invalid input. Must be in the form of SERVER:PATH" >&2
        else
          serverpath=$input
        fi
    done
    echo "${serverpath}"
}

function kube-nfs-shell() {
    serverpath=$1
    [[ -z "${serverpath}" ]] && serverpath=$(_get_nfs_info)

    IFS=':' read -ra toks <<< "${serverpath}"
    nfsserver=${toks[0]}
    nfspath=${toks[1]}
    echo "INFO: Creating pod with NFS mount ${nfsserver}:${nfspath} at /mnt/nfs" >&2

    read -r -d '' SPEC_JSON <<EOF
{
  "apiVersion": "v1",
  "spec": {
    "containers": [{
      "name": "shell",
      "command": ["bash"],
      "image": "debian:latest",
      "workingDir": "/mnt/nfs",
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "name": "nfs",
        "mountPath": "/mnt/nfs"
      }]
    }],
    "volumes": [{
      "name": "nfs",
      "nfs": {
        "server": "${nfsserver}",
        "path": "${nfspath}"
      }
    }]
  }
}
EOF
    id=$(printf "%x" $((RANDOM + 100000)))
    POD_NAME="nfs-shell-${id}"
    kubectl run -n ${KUBECTL_PLUGINS_CURRENT_NAMESPACE:-default} ${POD_NAME} -i -t --rm --restart=Never --image=debian:latest --overrides="${SPEC_JSON}"
}

kube-nfs-shell $@