#!/bin/bash

# Token écrit dans un fichier temporaire pour éviter "command line too long"
TOKEN_FILE=$(mktemp)
cat > "$TOKEN_FILE" << 'TOKENEOF'
eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJiMEk3X3VRWTRuemlqMlp1Ny1FRjQtUEwwZXpPWHFnWlRTMk9qelY2WE1zIn0.eyJleHAiOjE3Nzk3NDkwNzMsImlhdCI6MTc3OTc0ODc3MywiYXV0aF90aW1lIjoxNzc5NzQ1MzAyLCJqdGkiOiJvbnJ0cnQ6YzA3ZTkzOGYtMzMzNS01MTg0LTcxMzQtYmE5Y2ExZmJlYzI1IiwiaXNzIjoiaHR0cHM6Ly9lY29tLWFwaW0tZm9ybWF0aW9uLmF6dXJlLWFwaS5uZXQva2V5Y2xvYWsvcmVhbG1zL3VzZXIiLCJhdWQiOiJhY2NvdW50Iiwic3ViIjoiMzA3ZTVkYmYtMjliZS00ZGE0LThjNWQtY2RjZGU3YWQ1YjE4IiwidHlwIjoiQmVhcmVyIiwiYXpwIjoiZWNvbS1mcm9udGVuZCIsInNpZCI6Ind0QzhXZzVFc2ZUWEVJbFFPVzE2QXU3QiIsImFjciI6IjEiLCJhbGxvd2VkLW9yaWdpbnMiOlsiaHR0cHM6Ly8yMC40My41OS4yMjYiXSwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbIm9mZmxpbmVfYWNjZXNzIiwidW1hX2F1dGhvcml6YXRpb24iLCJkZWZhdWx0LXJvbGVzLXVzZXIiXX0sInJlc291cmNlX2FjY2VzcyI6eyJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJuYW1lIjoianViYSB0b3VhbSIsInByZWZlcnJlZF91c2VybmFtZSI6Imp1YmEiLCJnaXZlbl9uYW1lIjoianViYSIsImZhbWlseV9uYW1lIjoidG91YW0iLCJlbWFpbCI6Imp1YmF0b3VhbTYxQGdtYWlsLmNvbSJ9.keY_DnS2-2dyhxvqq0vRFlBeN5uSYjRzrL61i6PBjgaRaO8DN_oPCUD1GAyzAu4vo1uyzd0PCH13gwBubJmMHfz-KL3YwpZXFxKXBnBwy3utyYyfeKptUQKRfHNqhz_4tZyXp32R_KVjrf_hi8jncgpNyKe1ULdy2Az2sjQMiRg-9JB-XzOUoV5uyTY6mG2fDTNg0LUZzBLp0e3tZySXhWlM_sDtUm9T3yNMqba5dGd5IrDqL1DwjSThOGooYSXoJ7c_g6qbM95h0Ee48yskmEyiuEcWC_7e1l4-4ufpfAPcA3xv4Kub5QJ-0uFXNrcdsX0gFCTQeIFUviRiWU8crQ
TOKENEOF

TOTAL=70
CONCURRENCY=20
TMPDIR_RESULTS=$(mktemp -d)

do_request() {
  i=$1
  TOKEN_FILE=$2
  OUTFILE=$3
  TOKEN=$(cat "$TOKEN_FILE")

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -H "Authorization: Bearer $TOKEN" \
    "https://ecom-apim-formation.azure-api.net/api/orders")

  echo "$i $STATUS" > "$OUTFILE/$i"
}

export -f do_request

# date compatible macOS (pas de %3N)
START=$(python3 -c "import time; print(int(time.time() * 1000))")

seq 1 $TOTAL | xargs -P $CONCURRENCY -I {} bash -c "do_request {} \"$TOKEN_FILE\" \"$TMPDIR_RESULTS\""

END=$(python3 -c "import time; print(int(time.time() * 1000))")
ELAPSED=$(( END - START ))

OK=0; R429=0; ERR=0; FIRST429=""

for i in $(seq 1 $TOTAL); do
  if [ -f "$TMPDIR_RESULTS/$i" ]; then
    read IDX STATUS < "$TMPDIR_RESULTS/$i"
    if [ "$STATUS" = "200" ]; then
      OK=$((OK+1))
    elif [ "$STATUS" = "429" ]; then
      R429=$((R429+1))
      [ -z "$FIRST429" ] && FIRST429=$i
    else
      ERR=$((ERR+1))
      echo "#$(printf '%03d' $i) ✗ $STATUS"
    fi
  fi
done

rm -rf "$TMPDIR_RESULTS"
rm -f "$TOKEN_FILE"

echo ""
echo "================================"
echo "  RÉSULTAT DU TEST RATE LIMIT"
echo "================================"
echo "  Durée        : ${ELAPSED}ms"
echo "  200 OK       : $OK"
echo "  429 Limités  : $R429"
echo "  Erreurs      : $ERR"
echo "  Premier 429  : #${FIRST429:-aucun} (attendu #201)"
echo "================================"

if [ -n "$FIRST429" ]; then
  if [ "$FIRST429" -ge 199 ] && [ "$FIRST429" -le 203 ]; then
    echo "  ✅ Rate limiting FONCTIONNEL"
  else
    echo "  ⚠️  429 détecté mais limite inattendue (#$FIRST429)"
  fi
else
  echo "  ❌ Aucun 429 — Rate limiting non actif ?"
fi
echo "================================"
