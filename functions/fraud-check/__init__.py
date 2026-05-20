"""
Azure Function : fraud-check
Appelée par APIM via <send-request> avant le routage vers le microservice payment.

Règles V1 :
  1. amount > 5000 €          → deny
  2. IP présente en blacklist  → deny
  3. > 5 paiements / user / 10 min → deny
  4. Sinon                     → allow

Retour JSON : { "decision": "allow" | "deny", "reason": "..." }
APIM lit `decision` et bloque avec 403 si "deny".
"""

import json
import logging
import os
import time
from collections import defaultdict
from datetime import datetime, timezone

import azure.functions as func

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Blacklist d'IPs — en production, à stocker dans Azure Table Storage ou
# Key Vault et à recharger périodiquement.
# La variable d'environnement BLACKLISTED_IPS est une liste CSV d'IPs.
# ---------------------------------------------------------------------------
def _load_blacklist() -> set[str]:
    raw = os.environ.get("BLACKLISTED_IPS", "")
    return {ip.strip() for ip in raw.split(",") if ip.strip()}


# ---------------------------------------------------------------------------
# Velocity store in-memory (limité à une seule instance Function).
# En production, remplacer par Azure Cache for Redis ou Table Storage pour
# un stockage distribué entre les instances.
# ---------------------------------------------------------------------------
_velocity_store: dict[str, list[float]] = defaultdict(list)

VELOCITY_WINDOW_SECONDS = int(os.environ.get("VELOCITY_WINDOW_SECONDS", "600"))  # 10 min
VELOCITY_MAX_CALLS = int(os.environ.get("VELOCITY_MAX_CALLS", "5"))
AMOUNT_LIMIT = float(os.environ.get("AMOUNT_LIMIT", "5000"))


def _check_velocity(user_id: str) -> bool:
    """
    Retourne True si l'utilisateur dépasse le seuil de vélocité.
    Nettoie les timestamps expirés à chaque appel.
    """
    now = time.monotonic()
    cutoff = now - VELOCITY_WINDOW_SECONDS

    # Purge des timestamps hors fenêtre
    _velocity_store[user_id] = [
        ts for ts in _velocity_store[user_id] if ts > cutoff
    ]

    if len(_velocity_store[user_id]) >= VELOCITY_MAX_CALLS:
        return True  # seuil atteint → deny

    # Enregistre cet appel (avant la décision finale ; si deny, on ne comptabilise
    # pas un vrai paiement mais on incrémente quand même pour protéger contre le
    # flood de requêtes malveillantes).
    _velocity_store[user_id].append(now)
    return False


def _deny(reason: str) -> func.HttpResponse:
    logger.warning("FRAUD DENY — %s", reason)
    body = json.dumps({"decision": "deny", "reason": reason})
    return func.HttpResponse(body, status_code=200, mimetype="application/json")


def _allow() -> func.HttpResponse:
    logger.info("FRAUD ALLOW")
    body = json.dumps({"decision": "allow", "reason": "ok"})
    return func.HttpResponse(body, status_code=200, mimetype="application/json")


def main(req: func.HttpRequest) -> func.HttpResponse:
    logger.info(
        "fraud-check triggered — method=%s url=%s", req.method, req.url
    )

    # ------------------------------------------------------------------
    # 1. Parsing du body
    # ------------------------------------------------------------------
    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"decision": "deny", "reason": "invalid_json"}),
            status_code=400,
            mimetype="application/json",
        )

    amount: float | None = payload.get("amount")
    user_id: str | None = payload.get("user_id")
    # L'IP peut être transmise par APIM dans le body ou dans un header dédié.
    # APIM forward l'IP cliente via le header X-Forwarded-For ou via le body.
    client_ip: str = (
        payload.get("client_ip")
        or req.headers.get("X-Forwarded-For", "").split(",")[0].strip()
        or req.headers.get("X-Real-IP", "unknown")
    )

    logger.info(
        "Payload — amount=%s user_id=%s client_ip=%s", amount, user_id, client_ip
    )

    # ------------------------------------------------------------------
    # 2. Validation des champs obligatoires
    # ------------------------------------------------------------------
    if amount is None:
        return func.HttpResponse(
            json.dumps({"decision": "deny", "reason": "missing_field:amount"}),
            status_code=400,
            mimetype="application/json",
        )
    if not user_id:
        return func.HttpResponse(
            json.dumps({"decision": "deny", "reason": "missing_field:user_id"}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        amount = float(amount)
    except (TypeError, ValueError):
        return func.HttpResponse(
            json.dumps({"decision": "deny", "reason": "invalid_field:amount"}),
            status_code=400,
            mimetype="application/json",
        )

    # ------------------------------------------------------------------
    # Règle 1 — Montant trop élevé
    # ------------------------------------------------------------------
    if amount > AMOUNT_LIMIT:
        return _deny(f"amount_exceeded:{amount}>{AMOUNT_LIMIT}")

    # ------------------------------------------------------------------
    # Règle 2 — IP blacklistée
    # ------------------------------------------------------------------
    blacklist = _load_blacklist()
    if client_ip in blacklist:
        return _deny(f"blacklisted_ip:{client_ip}")

    # ------------------------------------------------------------------
    # Règle 3 — Velocity (> VELOCITY_MAX_CALLS en VELOCITY_WINDOW_SECONDS)
    # ------------------------------------------------------------------
    if _check_velocity(user_id):
        return _deny(
            f"velocity_exceeded:user={user_id} "
            f"limit={VELOCITY_MAX_CALLS}/{VELOCITY_WINDOW_SECONDS}s"
        )

    # ------------------------------------------------------------------
    # Toutes les règles passées → allow
    # ------------------------------------------------------------------
    return _allow()
