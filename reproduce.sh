#!/usr/bin/env bash

function die() {
    msg="$1"
    echo $msg
    exit 1
}

[[ -z "$1" ]] && die "Please provide URl of logs of reproduced jobs" || LOG_DIR=$1
shift
QUICKSTART_ARGS="$@"
rm -f /tmp/reproduce.me
wget ${LOG_DIR}/logs/reproduce.sh -O /tmp/reproduce.me \
|| die "Can not download ${LOG_DIR}/logs/reproduce.sh"


PROJ=$(grep -o 'ZUUL_PROJECT=".*"' /tmp/reproduce.me | cut -d'"' -f2)
REFS=$(grep -Eo 'ZUUL_CHANGES=".*"' /tmp/reproduce.me | cut -d'"' -f2 | tr -d '"')
BRANCH=$(grep -Eo 'ZUUL_BRANCH=".*"' /tmp/reproduce.me  | head -1 | cut -d'"' -f2)
REF_NUM=$(grep -Eo 'ZUUL_CHANGE=".*"' /tmp/reproduce.me | cut -d'"' -f2 | tr -d '"')

[[ "$BRANCH" != "master" ]] && die "Sorry, branch $BRANCH is not supported yet, only master"
for ref in  $(sed 's/\^/ /g' <<< "${REFS:-}"); do
    [[ "$ref" =~ "$PROJ" && "$ref" =~ "$REF_NUM" ]] && export ZUUL_V=$ref && break
done
[[ -z "${ZUUL_V:-}" ]] && die "Can not find project $PROJ with ref number $REF_NUM in ZUUL_CHANGES: $REFS"
[[ "$LOG_DIR" =~ "-ha" ]] && export CONFIG="ha" || export CONFIG="minimal"

export ZUUL_HOST="review.openstack.org"
export ZUUL_CHANGES=$ZUUL_V

echo "Reproducing with ZUUL_HOST=$ZUUL_HOST ZUUL_CHANGES=$ZUUL_CHANGES"
bash ./quickstart.sh \
        --no-clone \
        --bootstrap \
        --extra-vars artg_compressed_gating_repo="/home/stack/gating_repo.tar.gz" \
        --requirements ./quickstart-role-requirements.txt \
        --playbook dlrn-gate.yml \
        --tags all \
        --teardown all \
        --release "${BRANCH}-tripleo" \
        $QUICKSTART_ARGS $VIRTHOST || die "FATAL ERROR: can not build repo"
bash ./quickstart.sh \
        --no-clone \
        --retain-inventory \
        --extra-vars compressed_gating_repo="/home/stack/gating_repo.tar.gz" \
        --config ./config/general_config/$CONFIG.yml \
        --extra-vars @./config/general_config/devmode.yml \
        --extra-vars ooo_logs_path=$LOG_DIR \
        --playbook tripleo-roles.yml \
        --skip-tags provision,undercloud-post-install \
        --tags all \
        --teardown none \
        --release "${BRANCH}-tripleo" \
        $QUICKSTART_ARGS $VIRTHOST
