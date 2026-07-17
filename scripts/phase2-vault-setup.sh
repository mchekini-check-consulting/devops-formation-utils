#!/bin/bash
# phase2-vault-setup.sh
# Usage: ./scripts/phase2-vault-setup.sh <VAULT_ROOT_TOKEN>

set -euo pipefail

TOKEN=${1:?"Usage: $0 <VAULT_ROOT_TOKEN>"}
VAULT_CMD="kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$TOKEN vault"

echo "=== 1/3 Peupler les secrets ==="

# Catalog
$VAULT_CMD kv put secret/dev/catalog \
  DB_USER=formation \
  DB_PASSWORD=test

$VAULT_CMD kv put secret/prod/catalog \
  DB_USER=formation \
  DB_PASSWORD=test

# Order
$VAULT_CMD kv put secret/dev/order \
  POSTGRES_USER=formation \
  POSTGRES_PASSWORD=test \
  DJANGO_SECRET_KEY="django-insecure-aks-dev-change-in-prod"

$VAULT_CMD kv put secret/prod/order \
  POSTGRES_USER=formation \
  POSTGRES_PASSWORD=test \
  DJANGO_SECRET_KEY="django-insecure-aks-dev-change-in-prod"

# Payment
$VAULT_CMD kv put secret/dev/payment \
  SPRING_DATASOURCE_USERNAME=formation \
  SPRING_DATASOURCE_PASSWORD=test \
  APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=1311ad53-6ac0-4946-bb2f-48c60120bbd9;IngestionEndpoint=https://francecentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://francecentral.livediagnostics.monitor.azure.com/;ApplicationId=d9efc03e-0523-42cc-9e0e-1ea237ed1ba4"

$VAULT_CMD kv put secret/prod/payment \
  SPRING_DATASOURCE_USERNAME=formation \
  SPRING_DATASOURCE_PASSWORD=test \
  APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=1311ad53-6ac0-4946-bb2f-48c60120bbd9;IngestionEndpoint=https://francecentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://francecentral.livediagnostics.monitor.azure.com/;ApplicationId=d9efc03e-0523-42cc-9e0e-1ea237ed1ba4"

echo "=== 2/3 Creer les policies ==="

for env in dev prod; do
  for svc in catalog order payment; do
    echo "  policy: ${svc}-${env}"
    kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$TOKEN sh -c \
      "echo 'path \"secret/data/${env}/${svc}\" { capabilities = [\"read\"] }' | vault policy write ${svc}-${env} -"
  done
done

echo "  policy: eso-read-all"
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$TOKEN sh -c \
  "echo 'path \"secret/data/*\" { capabilities = [\"read\"] }' | vault policy write eso-read-all -"

echo "=== 3/3 Creer les roles Kubernetes ==="

# Roles par microservice
$VAULT_CMD write auth/kubernetes/role/catalog-dev \
  bound_service_account_names=catalogue \
  bound_service_account_namespaces=dev \
  policies=catalog-dev \
  ttl=1h

$VAULT_CMD write auth/kubernetes/role/catalog-prod \
  bound_service_account_names=catalogue \
  bound_service_account_namespaces=prod \
  policies=catalog-prod \
  ttl=1h

$VAULT_CMD write auth/kubernetes/role/order-dev \
  bound_service_account_names=order \
  bound_service_account_namespaces=dev \
  policies=order-dev \
  ttl=1h

$VAULT_CMD write auth/kubernetes/role/order-prod \
  bound_service_account_names=order \
  bound_service_account_namespaces=prod \
  policies=order-prod \
  ttl=1h

$VAULT_CMD write auth/kubernetes/role/payment-dev \
  bound_service_account_names=payment \
  bound_service_account_namespaces=dev \
  policies=payment-dev \
  ttl=1h

$VAULT_CMD write auth/kubernetes/role/payment-prod \
  bound_service_account_names=payment \
  bound_service_account_namespaces=prod \
  policies=payment-prod \
  ttl=1h

# Role ESO
$VAULT_CMD write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-read-all \
  ttl=1h

echo "=== Verification ==="
$VAULT_CMD kv get secret/dev/catalog
$VAULT_CMD policy list
$VAULT_CMD list auth/kubernetes/role

echo "=== Phase 2 terminee ==="
