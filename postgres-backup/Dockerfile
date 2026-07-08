FROM alpine:3.20
RUN apk add --no-cache postgresql16-client curl
RUN printf '#!/bin/sh\n\
set -eo pipefail\n\
BASENAME=$(date +%%Y%%m%%d-%%H%%M%%S)\n\
DUMP=${BASENAME}.sql.gz\n\
ARCHIVE=${BASENAME}.tar\n\
echo "[1/5] Dumping database..."\n\
pg_dumpall -h "$PG_HOST" -U "$PG_USER" | gzip > /tmp/$DUMP\n\
echo "[1/5] Dump complete ($(wc -c < /tmp/$DUMP) bytes)"\n\
echo "[2/5] Computing SHA256 checksum..."\n\
CHECKSUM=$(sha256sum /tmp/$DUMP | cut -d " " -f 1)\n\
echo "$CHECKSUM" > /tmp/${DUMP}.sha256\n\
echo "[2/5] Checksum: $CHECKSUM"\n\
echo "[3/5] Archiving dump + checksum..."\n\
tar cf /tmp/$ARCHIVE -C /tmp $DUMP ${DUMP}.sha256\n\
echo "[3/5] Archive created ($(wc -c < /tmp/$ARCHIVE) bytes)"\n\
echo "[4/5] Requesting Azure access token..."\n\
TOKEN=$(curl -sf -X POST \\\n\
  "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \\\n\
  -d "grant_type=client_credentials&client_id=${AZURE_CLIENT_ID}&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$(cat $AZURE_FEDERATED_TOKEN_FILE)&scope=https://storage.azure.com/.default" \\\n\
  | sed -n '"'"'s/.*"access_token":"\\([^"]*\\)".*/\\1/p'"'"')\n\
echo "[4/5] Token acquired"\n\
echo "[5/5] Uploading $ARCHIVE to Azure Blob Storage..."\n\
curl -sf -X PUT \\\n\
  -H "Authorization: Bearer ${TOKEN}" \\\n\
  -H "x-ms-blob-type: BlockBlob" \\\n\
  -H "x-ms-version: 2020-04-08" \\\n\
  -H "Content-Type: application/x-tar" \\\n\
  --data-binary @/tmp/$ARCHIVE \\\n\
  "https://stformationecombackup.blob.core.windows.net/postgres-backups/dev/${ARCHIVE}"\n\
echo "[5/5] Upload complete"\n' > /backup.sh && chmod +x /backup.sh
ENTRYPOINT ["/backup.sh"]
