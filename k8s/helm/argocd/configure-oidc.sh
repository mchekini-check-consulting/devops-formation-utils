#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# configure-oidc.sh — Configure le SSO Azure AD (OIDC) pour ArgoCD
#
# Prérequis :
#   - ArgoCD installé (./install.sh exécuté)
#   - Azure CLI (az) connecté avec les droits sur l'App Registration
#   - Client secret OIDC disponible (depuis Azure Portal)
#
# Actions :
#   1. Injecte le client secret OIDC dans le secret argocd-secret
#   2. Récupère l'IP externe du LoadBalancer
#   3. Met à jour l'URL d'ArgoCD dans argocd-cm
#   4. Enregistre l'URI de redirect dans Azure AD
#   5. Redémarre argocd-server pour appliquer les changements
# ---------------------------------------------------------------------------
set -euo pipefail

NAMESPACE="argocd"
# ID de l'App Registration Azure AD pour ArgoCD
APP_ID="58da4cc7-4763-4339-a0e5-8b8868a49049"

# Demande le client secret OIDC (saisie masquée)
echo "==> Patching OIDC client secret into argocd-secret..."
echo -n "Enter Azure AD OIDC client secret: "
read -rs OIDC_CLIENT_SECRET
echo

# Injecte le secret dans le Secret Kubernetes utilisé par ArgoCD
kubectl -n "${NAMESPACE}" patch secret argocd-secret \
  --type merge \
  -p "{\"stringData\":{\"oidc.azure.clientSecret\":\"${OIDC_CLIENT_SECRET}\"}}"

# Récupère l'IP externe du service LoadBalancer argocd-server
# Retry jusqu'à 30 fois (5 min) car l'IP peut mettre du temps à être provisionnée
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

# Met à jour l'URL publique d'ArgoCD (nécessaire pour les redirections OIDC)
echo "==> Configuring ArgoCD URL (https://${EXTERNAL_IP})..."
kubectl -n "${NAMESPACE}" patch configmap argocd-cm \
  --type merge \
  -p "{\"data\":{\"url\":\"https://${EXTERNAL_IP}\"}}"

# Enregistre l'URI de callback dans l'App Registration Azure AD
echo "==> Registering redirect URI in Azure AD..."
az ad app update --id "${APP_ID}" \
  --web-redirect-uris "https://${EXTERNAL_IP}/auth/callback"

# Redémarre le serveur pour prendre en compte les changements de config
echo "==> Restarting argocd-server to apply config changes..."
kubectl -n "${NAMESPACE}" rollout restart deployment/argocd-server
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-server

echo "==> OIDC configuration complete!"
echo "    SSO URL: https://${EXTERNAL_IP}/auth/callback"
