# devops-formation-utils

Utilitaires pour le deploiement de la plateforme e-commerce de formation.

---

## Functions

Azure Function App utilisee pour le fraud-check des paiements, appelee par APIM via `<send-request>` avant le routage vers le microservice payment.

### Structure

```
functions/
  host.json                  # Configuration du runtime Azure Functions v2
  requirements.txt           # Dependances Python (azure-functions)
  fraud-check/
    __init__.py              # Code de la function
    function.json            # Binding HTTP POST /fraud-check
```

### Regles de detection

| Regle | Condition | Decision |
|-------|-----------|----------|
| 1 | `amount > 5000` | deny |
| 2 | IP presente dans la blacklist (`BLACKLISTED_IPS`) | deny |
| 3 | Plus de 5 paiements par utilisateur en 10 min | deny |
| 4 | Sinon | allow |

### Variables d'environnement

| Variable | Description | Defaut |
|----------|-------------|--------|
| `BLACKLISTED_IPS` | Liste CSV d'IPs a bloquer | _(vide)_ |
| `VELOCITY_WINDOW_SECONDS` | Fenetre de temps pour la velocity | `600` |
| `VELOCITY_MAX_CALLS` | Nombre max d'appels par fenetre | `5` |
| `AMOUNT_LIMIT` | Montant max autorise | `5000` |

### Deploiement

> **Important** : A chaque `terraform apply` de la landing-zone, le code de la Function App est reinitialise. Il faut **systematiquement re-publier** la function apres chaque apply :
>
> ```bash
> func azure functionapp publish func-formation-ecom-fraud-check-dev --python
> ```

---

## Scripts

Scripts de provisionnement et de deploiement des VMs Azure (cloud-init / systemd).

### Structure

```
scripts/
  setup-vm.sh                    # Cloud-init : installe Docker et lance le deploiement
  create-service.sh              # Cree le service systemd deploy.service
  deploy.sh                      # Script principal de deploiement (login ACR + docker compose)
  docker-compose.back.yaml       # Compose backend (catalogue, order, payment)
  docker-compose.payment.yaml    # Compose payment seul (VM back-*-02)
  docker-compose.front.yaml      # Compose frontend (nginx + app)
  docker-compose.keycloak.yaml   # Compose Keycloak + PostgreSQL
  nginx.conf                     # Config Nginx (redirect HTTP -> HTTPS, TLS, SPA)
  setup-keycloak.sh              # Cloud-init Keycloak : Docker, TLS, compose, bootstrap realm
  config-keycloak-front.sh       # Configure le client OAuth2 ecom-frontend dans Keycloak
```

### Fonctionnement

#### setup-vm.sh

Execute par cloud-init au premier demarrage de la VM. Installe Docker, telecharge les scripts depuis GitHub et lance `create-service.sh`.

#### create-service.sh

Cree un service systemd `deploy.service` qui execute `deploy.sh` au demarrage de la VM.

#### deploy.sh

Script principal de deploiement :

1. Detecte l'environnement (dev/qua/prod) et le type de VM (front/back) via le hostname
2. Exporte les variables d'environnement correspondantes (images, tags, connexions DB)
3. S'authentifie aupres d'Azure Container Registry via managed identity (IMDS)
4. Sur les VMs front, recupere le certificat TLS depuis Key Vault
5. Lance le `docker compose` adapte au type de VM

#### setup-keycloak.sh

Script cloud-init pour la VM Keycloak :

1. Installe Docker
2. Genere un certificat TLS auto-signe
3. Demarre Keycloak + PostgreSQL via docker compose
4. Cree le realm `user` et l'utilisateur `platform-admin`

#### config-keycloak-front.sh

A executer manuellement apres le deploiement de Keycloak. Configure :

- Le client OAuth2 `ecom-frontend` (public, SPA)
- L'URL frontend du realm via APIM
- L'inscription utilisateur (self-registration)
- Le role `admin` assigne a `platform-admin`
- L'utilisateur de test `user-standard`

---

## Test post-deploy

Scripts de test pour valider le bon fonctionnement de la plateforme apres un deploiement.

### Structure

```
scripts/test-post-deploy/
  test-cache.sh          # Compare les temps de reponse APIM sans cache vs avec cache
  test-cache-miss.sh     # Premier appel pour verifier un cache MISS
```

### Prerequis

Exporter un token Bearer valide avant d'executer les scripts :

```bash
export TOKEN="<votre_token>"
```

### test-cache.sh

Effectue deux appels successifs sur `/api/products` :

1. **Sans cache** : envoie `Cache-Control: no-cache, no-store` pour forcer un appel au backend
2. **Avec cache** : appel normal, le cache APIM doit repondre

Affiche le TTFB, le temps total et les headers de cache (`X-Cache`, `Age`, `ETag`).

### test-cache-miss.sh

Effectue un seul appel sur `/api/products/` et affiche la reponse complete avec headers. Utile pour verifier qu'un premier appel produit un cache MISS.
