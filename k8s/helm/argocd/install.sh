#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh — Installe ArgoCD via Helm sur le cluster Kubernetes
#
# Prérequis :
#   - kubectl configuré et connecté au cluster
#   - helm installé
#
# Étapes suivantes après exécution :
#   1. kubectl apply -f repo-gitops-secret.yaml  (credentials repo GitOps)
#   2. kubectl apply -f root-app.yaml            (App-of-Apps root-app)
#   (SSO: pas configuré pour l'instant, voir configure-oidc.sh — Azure AD,
#    à remplacer par un équivalent AWS IAM Identity Center si besoin)
# ---------------------------------------------------------------------------
set -euo pipefail

NAMESPACE="argocd"
RELEASE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ajoute le repo Helm officiel d'ArgoCD (ignore si déjà présent)
echo "==> Adding Argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

# Crée le namespace argocd (idempotent grâce à dry-run + apply)
echo "==> Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Installe ou met à jour ArgoCD avec les values personnalisées
echo "==> Installing/upgrading ArgoCD..."
helm upgrade --install "${RELEASE}" argo/argo-cd \
  -n "${NAMESPACE}" \
  -f "${SCRIPT_DIR}/values.yaml"

# Attend que le serveur ArgoCD soit prêt
echo "==> Waiting for argocd-server rollout..."
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-server

# Affiche le mot de passe admin initial (généré automatiquement par ArgoCD)
echo "==> ArgoCD initial admin password:"
kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo

echo ""
echo "==> Installation complete!"
echo "    Next steps:"
echo "    1. kubectl apply -f repo-gitops-secret.yaml  (credentials repo GitOps)"
echo "    2. kubectl apply -f root-app.yaml            (App-of-Apps root-app)"
