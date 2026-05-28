#!/bin/bash
# Test cache APIM : premier appel (MISS attendu)

echo "=== Appel 1 (MISS attendu) ===" && \
curl -s -w "\nTemps: %{time_total}s\n" \
  -H "Authorization: Bearer $TOKEN" \
  -D - \
  https://ecom-apim-formation.azure-api.net/api/products/
