#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="postgres-backup"

read -rp "Nom du fichier backup à restaurer (ex: 20260627-180413.tar): " BACKUP_FILENAME

if [ -z "$BACKUP_FILENAME" ]; then
  echo "Erreur: nom de fichier requis."
  exit 1
fi

export BACKUP_FILENAME

kubectl delete job pg-restore -n "$NAMESPACE" --ignore-not-found
envsubst '${BACKUP_FILENAME}' < "$SCRIPT_DIR/04-restore-job.yaml" | kubectl apply -f -

echo "Job de restore créé avec le backup: $BACKUP_FILENAME"
