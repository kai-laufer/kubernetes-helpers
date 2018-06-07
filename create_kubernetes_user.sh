#!/bin/bash

# 2018-06-07 Kai Laufer: This script creates a user in a given namespace.
# ATTENTION: kubectl is required!
# This script has been tested only on Debian Systems.

readonly PROG_NAME=$(basename $0)
readonly PROG_PATH=$(readlink -m $(dirname $0))
readonly PROG_VERSION='0.1'
readonly TMP_DIR="/tmp"
readonly KUBE_CRT_DIR="/etc/kubernetes/pki"
readonly API_SERVER="IP of your APISERVER"

print_help() {
        echo "${PROG_NAME} creates a Kubernetes User (for Dashboard and kubectl)."
        echo ""
        echo "  --help      | -h     = Print this help"
        echo "  --user      | -u     = User who should be created"
        echo "  --namespace | -n     = Namespace which should be created or used"
        echo ""
        echo "  EXAMPLES:"
        echo "          ${PROG_PATH}/${PROG_NAME} --user $(whoami) --namespace example"
        echo ""
        exit 3;
}

# Check given arguments
while test -n "$1"; do
        case "$1" in
                --help|-h)
                        print_help
                        ;;
                --version|-v)
                        echo ${PROG_VERSION}
                        exit 3;
                        ;;
                --user|-u)
                        USER=${2}
                        shift
                        ;;
                --namespace|-n)
                        NAMESPACE=${2}
                        shift
                        ;;
                *)
                        echo "Unknown argument: ${1}"
                        print_help
                        exit 3;
                        ;;
        esac
        shift
done

function success() {
	echo -en "\\033[32m${@}\n\033[0m"
}

function warning() {
        echo -en "\\033[33m${@}\n\033[0m"
}

function info() {
        echo -en "\\033[36m${@}\n\033[0m"
}

function important() {
        echo -en "\\033[93m${@}\n\033[0m"
}

if [[ -z ${USER} || -z ${NAMESPACE} ]]; then
	echo "ERROR: Missing arguments..."
	print_help
	exit 1
fi

readonly USER_FILE="/tmp/kubernetes_user_${USER}_${NAMESPACE}_${RANDOM}.token"
readonly USER_CONFIG="/tmp/kubernetes_user_${USER}_${NAMESPACE}_${RANDOM}.config"

# YAML for creating the user
echo "kind: Namespace
apiVersion: v1
metadata:
  name: ${NAMESPACE}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${USER}
  namespace: ${NAMESPACE}
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: ${NAMESPACE}
  name: ${USER}-role
rules:
  - apiGroups: [\"*\"]
    resources: [\"*\"]
    verbs: [\"*\"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: ${USER}-role-${USER}-all-members
  namespace: ${NAMESPACE}
subjects:
  - kind: User
    name: ${USER}
  - kind: Group
    name: ${USER}
  - kind: Group
    name: system:serviceaccounts:${USER}
roleRef:
  kind: Role
  name: ${USER}-role
  apiGroup: \"rbac.authorization.k8s.io\"
" > ${USER_FILE}

# Creating dashboard user and user for command line on this host
info "#############################################################################################################"
info "Creating user for dashboard...."
info "#############################################################################################################"
kubectl create -f ${USER_FILE}
echo -e
info "#############################################################################################################"
info "Copy/save this token for dashboard access."
info "#############################################################################################################"
important "$(kubectl -n ${NAMESPACE} describe secret $(kubectl -n ${NAMESPACE} get secret | grep ${USER} | awk '{print $1}'))"
rm -rf ${USER_FILE}
success "==> User for dashboard and command line on $(hostname) has been created!"
echo -e
info "#############################################################################################################"
info "Creating user certificates for local command line usage..."
info "#############################################################################################################"

openssl genrsa -out ${TMP_DIR}/${USER}.key 2048
# Certificates will be valid for five years...
# Change O= if required
openssl req -days 1825 -new -key ${TMP_DIR}/${USER}.key -out ${TMP_DIR}/${USER}.csr -subj "/CN=${USER}/O=FOOBAR"
openssl x509 -req -in ${TMP_DIR}/${USER}.csr -CA ${KUBE_CRT_DIR}/ca.crt -CAkey ${KUBE_CRT_DIR}/ca.key -CAcreateserial -out ${TMP_DIR}/${USER}.crt -days 1825
kubectl config set-credentials ${USER} --client-certificate=${TMP_DIR}/${USER}.crt  --client-key=${TMP_DIR}/${USER}.key
success "==> Created certificates and permissions for external and/or local usage of kubectl."

# Creating config
echo "apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $(cat ${KUBE_CRT_DIR}/ca.crt | base64 | tr -d '\n')
    server: https://${API_SERVER}:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: ${NAMESPACE}
    user: ${USER}
  name: ${USER}
current-context: ${USER}
kind: Config
preferences: {}
users:
- name: ${USER}
  user:
    as-user-extra: {}
    client-certificate-data: $(cat ${TMP_DIR}/${USER}.crt | base64 | tr -d '\n')
    client-key-data: $(cat ${TMP_DIR}/${USER}.key | base64 | tr -d '\n')
" > ${USER_CONFIG}

info "#############################################################################################################"
info "Copy this config to /your/home/.kube/config:"
info "#############################################################################################################"
important "$(cat ${USER_CONFIG})"
echo -e
rm ${USER_CONFIG} ${TMP_DIR}/${USER}.crt ${TMP_DIR}/${USER}.csr ${TMP_DIR}/${USER}.key
echo -e
warning "#############################################################################################################"
warning "ATTENTION: If this user already exists, please ignore the token and use the old token."
warning "#############################################################################################################"
exit 0
