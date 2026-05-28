#!/bin/bash
# Test du cache APIM : compare un appel sans cache vs avec cache

echo "--- SANS CACHE ---" && \
curl -s -D - -o /dev/null \
  -w "TTFB: %{time_starttransfer}s | Total: %{time_total}s | HTTP: %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Cache-Control: no-cache, no-store" \
  "https://ecom-apim-formation.azure-api.net/api/products" \
| grep -E "HTTP|X-Cache|x-cache|Age|ETag|TTFB" \
&& sleep 1 \
&& echo "" \
&& echo "--- AVEC CACHE ---" && \
curl -s -D - -o /dev/null \
  -w "TTFB: %{time_starttransfer}s | Total: %{time_total}s | HTTP: %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  "https://ecom-apim-formation.azure-api.net/api/products" \
| grep -E "HTTP|X-Cache|x-cache|Age|ETag|TTFB"
