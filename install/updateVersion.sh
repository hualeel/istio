#!/bin/bash

# Copyright 2017 Istio Authors
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at

#       http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License

# This file is temporary compatibility between old update version
# and helm template based generation
set -e
set -o errexit
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
VERSION_FILE="istio.VERSION"
TEMP_DIR="/tmp"
DEST_DIR=$ROOT

# set the default values
ISTIO_NAMESPACE="istio-system"
FORTIO_HUB="docker.io/fortio"
FORTIO_TAG="latest_release"

function usage() {
  cat <<EOF
usage: ${BASH_SOURCE[0]} [options ...]
  options:
    -p ... <hub>,<tag> for the pilot docker image
    -x ... <hub>,<tag> for the mixer docker image
    -c ... <hub>,<tag> for the citadel docker image
    -g ... <hub>,<tag> for the galley docker image
    -a ... <hub>,<tag> Specifies same hub and tag for pilot, mixer, proxy, citadel and galley containers
    -o ... <hub>,<tag> for the proxy docker image
    -n ... <namespace> namespace in which to install Istio control plane components
    -P ... URL to download pilot debian packages
    -d ... directory to store file (optional, defaults to source code tree)
EOF
  exit 2
}

while getopts :n:p:x:c:g:a:h:o:P:d: arg; do
  case ${arg} in
    n) ISTIO_NAMESPACE="${OPTARG}";;
    p) PILOT_HUB_TAG="${OPTARG}";;     # Format: "<hub>,<tag>"
    x) MIXER_HUB_TAG="${OPTARG}";;     # Format: "<hub>,<tag>"
    c) CITADEL_HUB_TAG="${OPTARG}";;   # Format: "<hub>,<tag>"
    g) GALLEY_HUB_TAG="${OPTARG}";;    # Format: "<hub>,<tag>"
    a) ALL_HUB_TAG="${OPTARG}";;       # Format: "<hub>,<tag>"
    o) PROXY_HUB_TAG="${OPTARG}";;     # Format: "<hub>,<tag>"
    P) PILOT_DEBIAN_URL="${OPTARG}";;
    d) DEST_DIR="${OPTARG}";;
    *) usage;;
  esac
done

if [[ -n ${ALL_HUB_TAG} ]]; then
    PILOT_HUB="$(echo "${ALL_HUB_TAG}"|cut -f1 -d,)"
    PILOT_TAG="$(echo "${ALL_HUB_TAG}"|cut -f2 -d,)"
    PROXY_HUB="$(echo "${ALL_HUB_TAG}"|cut -f1 -d,)"
    PROXY_TAG="$(echo "${ALL_HUB_TAG}"|cut -f2 -d,)"
    MIXER_HUB="$(echo "${ALL_HUB_TAG}"|cut -f1 -d,)"
    MIXER_TAG="$(echo "${ALL_HUB_TAG}"|cut -f2 -d,)"
    CITADEL_HUB="$(echo "${ALL_HUB_TAG}"|cut -f1 -d,)"
    CITADEL_TAG="$(echo "${ALL_HUB_TAG}"|cut -f2 -d,)"
    GALLEY_HUB="$(echo "${ALL_HUB_TAG}"|cut -f1 -d,)"
    GALLEY_TAG="$(echo "${ALL_HUB_TAG}"|cut -f2 -d,)"
fi

if [[ -n ${PROXY_HUB_TAG} ]]; then
    PROXY_HUB="$(echo "${PROXY_HUB_TAG}"|cut -f1 -d,)"
    PROXY_TAG="$(echo "${PROXY_HUB_TAG}"|cut -f2 -d,)"
fi

if [[ -n ${PILOT_HUB_TAG} ]]; then
    PILOT_HUB="$(echo "${PILOT_HUB_TAG}"|cut -f1 -d,)"
    PILOT_TAG="$(echo "${PILOT_HUB_TAG}"|cut -f2 -d,)"
fi

if [[ -n ${MIXER_HUB_TAG} ]]; then
    MIXER_HUB="$(echo "${MIXER_HUB_TAG}"|cut -f1 -d,)"
    MIXER_TAG="$(echo "${MIXER_HUB_TAG}"|cut -f2 -d,)"
fi

if [[ -n ${CITADEL_HUB_TAG} ]]; then
    CITADEL_HUB="$(echo "${CITADEL_HUB_TAG}"|cut -f1 -d,)"
    CITADEL_TAG="$(echo "${CITADEL_HUB_TAG}"|cut -f2 -d,)"
fi

if [[ -n ${GALLEY_HUB_TAG} ]]; then
    GALLEY_HUB="$(echo "${GALLEY_HUB_TAG}"|cut -f1 -d,)"
    GALLEY_TAG="$(echo "${GALLEY_HUB_TAG}"|cut -f2 -d,)"
fi

function error_exit() {
  # ${BASH_SOURCE[1]} is the file name of the caller.
  echo "${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}: ${1:-Unknown Error.} (exit ${2:-1})" 1>&2
  exit "${2:-1}"
}

#
# In-place portable sed operation
# the sed -i operation is not defined by POSIX and hence is not portable
#
function execute_sed() {
  sed -e "${1}" "$2" > "$2.new"
  mv -- "$2.new" "$2"
}

function update_version_file() {
  cat <<EOF > "${DEST_DIR}/${VERSION_FILE}"
# DO NOT EDIT THIS FILE MANUALLY instead use
# install/updateVersion.sh (see install/README.md)
export GALLEY_HUB="${GALLEY_HUB}"
export GALLEY_TAG="${GALLEY_TAG}"
export CITADEL_HUB="${CITADEL_HUB}"
export CITADEL_TAG="${CITADEL_TAG}"
export MIXER_HUB="${MIXER_HUB}"
export MIXER_TAG="${MIXER_TAG}"
export PILOT_HUB="${PILOT_HUB}"
export PILOT_TAG="${PILOT_TAG}"
export PROXY_HUB="${PROXY_HUB}"
export PROXY_TAG="${PROXY_TAG}"
export ISTIO_NAMESPACE="${ISTIO_NAMESPACE}"
export PILOT_DEBIAN_URL="${PILOT_DEBIAN_URL}"
export FORTIO_HUB="${FORTIO_HUB}"
export FORTIO_TAG="${FORTIO_TAG}"
EOF
}

function gen_file() {
    fl=$1
    dest=$2
    cd "$ROOT"; make "$1"   # make always places the files in install/...
    # If the two paths are not to the same file.
    if [[ ! install/kubernetes/$fl -ef ${dest}/install/kubernetes/$fl ]]; then
      # Potentially overwrites the file generated by updateVersion_orig.sh.
      cp -f "install/kubernetes/$fl" "${dest}/install/kubernetes/$fl"
    fi
}

function gen_istio_files() {
    for target in istio-demo.yaml istio-demo-auth.yaml; do
        gen_file $target "${DEST_DIR}"
    done
}

function update_istio_install_docker() {
  pushd $TEMP_DIR/templates
  execute_sed "s|image: {PILOT_HUB}/\\(.*\\):{PILOT_TAG}|image: ${PILOT_HUB}/\\1:${PILOT_TAG}|" istio.yaml.tmpl
  execute_sed "s|image: {PROXY_HUB}/\\(.*\\):{PROXY_TAG}|image: ${PROXY_HUB}/\\1:${PROXY_TAG}|" bookinfo.sidecars.yaml.tmpl
  popd
}

# Generated merge yaml files for easy installation
function merge_files_docker() {
  TYPE=$1
  SRC=$TEMP_DIR/templates

  # Merge istio.yaml install file
  INSTALL_DEST=$DEST_DIR/install/$TYPE
  ISTIO=${INSTALL_DEST}/istio.yaml

  mkdir -p "$INSTALL_DEST"
  echo "# GENERATED FILE. Use with Docker-Compose and ${TYPE}" > "$ISTIO"
  echo "# TO UPDATE, modify files in install/${TYPE}/templates and run install/updateVersion.sh" >> "$ISTIO"
  cat $SRC/istio.yaml.tmpl >> "$ISTIO"

  # Merge bookinfo.sidecars.yaml sample file
  SAMPLES_DEST=$DEST_DIR/samples/bookinfo/platform/$TYPE
  BOOKINFO=${SAMPLES_DEST}/bookinfo.sidecars.yaml

  mkdir -p "$SAMPLES_DEST"
  echo "# GENERATED FILE. Use with Docker-Compose and ${TYPE}" > "$BOOKINFO"
  echo "# TO UPDATE, modify files in samples/bookinfo/platform/${TYPE}/templates and run install/updateVersion.sh" >> "$BOOKINFO"
  cat $SRC/bookinfo.sidecars.yaml.tmpl >> "$BOOKINFO"
}

function gen_platforms_files() {
    # This loop only executes once, with platform=consul.
    # shellcheck disable=SC2043
    for platform in consul; do
        cp -R "$ROOT/install/$platform/templates" $TEMP_DIR/templates
        cp -a "$ROOT/samples/bookinfo/platform/$platform/templates/." $TEMP_DIR/templates/
        update_istio_install_docker
        merge_files_docker $platform
        rm -R $TEMP_DIR/templates
    done
}

#
# Script work begins here
#

# Create the destination dir if necessary
if [[ "$DEST_DIR" != "$ROOT" ]]; then
  if [ ! -d "$DEST_DIR" ]; then
    mkdir -p "$DEST_DIR"
  fi
  cp -R "$ROOT/install" "$DEST_DIR/"
  cp -R "$ROOT/samples" "$DEST_DIR/"
fi

# Set the HUB and TAG to be picked by the Helm template
if [[ -n ${ALL_HUB_TAG} ]]; then
    HUB="$(echo "${ALL_HUB_TAG}"|cut -f1 -d,)"
    export HUB
    TAG="$(echo "${ALL_HUB_TAG}"|cut -f2 -d,)"
    export TAG
fi

# Update the istio.VERSION file
update_version_file

# Generate the istio*.yaml files
gen_istio_files

# Generate platform files (consul)
gen_platforms_files
