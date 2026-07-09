#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="argocd"
RELEASE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ID="58da4cc7-4763-4339-a0e5-8b8868a49049"

echo "==> Adding Argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

echo "==> Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing/upgrading ArgoCD..."
helm upgrade --install "${RELEASE}" argo/argo-cd \
  -n "${NAMESPACE}" \
  -f "${SCRIPT_DIR}/values.yaml"

echo "==> Patching OIDC client secret into argocd-secret..."
echo -n "Enter Azure AD OIDC client secret: "
read -rs OIDC_CLIENT_SECRET
echo

kubectl -n "${NAMESPACE}" patch secret argocd-secret \
  --type merge \
  -p "{\"stringData\":{\"oidc.azure.clientSecret\":\"${OIDC_CLIENT_SECRET}\"}}"

echo "==> Waiting for argocd-server rollout..."
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-server

echo "==> Retrieving LoadBalancer external IP..."
EXTERNAL_IP=""
RETRIES=30
for i in $(seq 1 $RETRIES); do
  EXTERNAL_IP=$(kubectl -n "${NAMESPACE}" get svc argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || true)
  if [ -n "${EXTERNAL_IP}" ]; then
    break
  fi
  echo "    Waiting for external IP... (${i}/${RETRIES})"
  sleep 10
done

if [ -z "${EXTERNAL_IP}" ]; then
  echo "ERROR: Could not get external IP after ${RETRIES} attempts"
  exit 1
fi

echo "==> External IP: ${EXTERNAL_IP}"

echo "==> Configuring ArgoCD URL (https://${EXTERNAL_IP})..."
kubectl -n "${NAMESPACE}" patch configmap argocd-cm \
  --type merge \
  -p "{\"data\":{\"url\":\"https://${EXTERNAL_IP}\"}}"

echo "==> Registering redirect URI in Azure AD..."
az ad app update --id "${APP_ID}" \
  --web-redirect-uris "https://${EXTERNAL_IP}/auth/callback"

echo "==> Restarting argocd-server to apply config changes..."
kubectl -n "${NAMESPACE}" rollout restart deployment/argocd-server
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-server

echo "==> ArgoCD initial admin password:"
kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo

echo "==> Creating App-of-Apps bootstrap (root-app)..."
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/mchekini-check-consulting/devops-formation-gitops.git
    targetRevision: main
    path: bootstrap/
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo ""
echo "==> Installation complete!"
echo "    UI: https://${EXTERNAL_IP}"
echo "    Login: admin / <password above>"
echo "    SSO: Click 'Log in via Azure AD'"
