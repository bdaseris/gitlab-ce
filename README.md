# Déploiement de GitLab CE avec Docker Swarm pour Seris

Ce guide décrit comment déployer et gérer une instance GitLab CE dans un environnement Docker Swarm pour l'entreprise **Seris**. Il inclut les prérequis, la configuration des volumes persistants, la gestion des secrets et les étapes pour réinitialiser l'instance si nécessaire.

---

## Prérequis

* Docker CE installé sur la machine hôte (Ubuntu 24.04 ou similaire)
* Docker Compose (version compatible avec Swarm)
* Accès root ou sudo sur la machine hôte
* Ports ouverts :

  * SSH GitLab : 2222 (ou un autre si personnalisé)
  * HTTP : 80
  * HTTPS : 443

---

## Étape 1 : Initialiser le mode Swarm

Si le Docker Swarm n'est pas encore activé sur le serveur hôte :

```bash
docker swarm init
```

> Cela permet d'utiliser `docker stack deploy` et de gérer les services en mode Swarm.

---

## Étape 2 : Préparer les volumes persistants

1. Créer les répertoires sur la VM pour les données GitLab (incluant le répertoire pour les certificats SSL) :

```bash
sudo rm -rf /data/gitlab/*
sudo mkdir -p /data/gitlab/data /data/gitlab/logs /data/gitlab/config /data/gitlab/certs
sudo chown -R 1000:1000 /data/gitlab
```

> **Important** : le répertoire `/data/gitlab/certs` doit contenir les certificats TLS utilisés par GitLab (si vous activez HTTPS). Placez les fichiers avec les noms exacts ci‑dessous :
>
> * `/data/gitlab/certs/gitlab.securit.fr.crt`
> * `/data/gitlab/certs/gitlab.securit.fr.key`
>
> Ces chemins correspondent à la configuration `gitlab.rb` (`gitlab_rails['nginx']['ssl_certificate']` et `ssl_certificate_key`).

2. Copier `.env.example` vers `.env` et adapter les valeurs :

```bash
cp .env.example .env
```

Exemple de contenu (voir `.env.example`) :

```bash
GITLAB_HOME=/data/gitlab

# URL complète pour Omnibus (external_url) — avec schéma http/https
GITLAB_EXTERNAL_URL=http://gitlab.local
# Hostname seul (sans schéma) pour Docker hostname, aliases réseau et runners
GITLAB_HOSTNAME=gitlab.local

# IP de la VM hôte : utilisée par les containers de job CI pour résoudre GITLAB_HOSTNAME
GITLAB_HOST_IP=172.16.100.121

# SMTP (valeurs non sensibles — le mot de passe est géré via Docker secret)
SMTP_ADDRESS=mta.securit.fr
SMTP_PORT=587
SMTP_USER_NAME="GitLab Notifier <gitlab-info@seris.fr>"
SMTP_DOMAIN=securit.fr
```

> Le fichier `.env` n'est **pas versionné** (`.gitignore`). Le `Makefile` le charge automatiquement (`include .env` + `export`), et ces variables sont substituées dans `docker-compose.yml` puis lues par `gitlab.rb` via `ENV['...']`.
>
> **`GITLAB_EXTERNAL_URL`** : URL complète (ex. `http://gitlab.local` ou `https://gitlab.securit.fr`) — utilisée pour `external_url` et l'enregistrement des runners.
>
> **`GITLAB_HOSTNAME`** : nom d'hôte seul, **sans** `http://` (ex. `gitlab.local`) — utilisé pour le hostname Docker, les aliases réseau Swarm et la résolution DNS dans les jobs CI.
>
> Si vous déployez sans le Makefile, exportez d'abord les variables dans le shell (y compris le hash de la config, cf. plus bas) :
>
> ```bash
> set -a; source .env; set +a
> export GITLAB_CONFIG_HASH=$(md5sum docker/gitlab/gitlab.rb | cut -c1-8)
> ```
>
> **Note** : les configs Docker Swarm sont **immuables**. Le nom de la config (`gitlab_conf_<hash>`) inclut le hash de `gitlab.rb` : toute modification du fichier crée une nouvelle config au lieu d'échouer avec l'erreur `only updates to Labels are allowed`. Le Makefile calcule ce hash automatiquement et supprime les anciennes configs après chaque déploiement.

3. Vérifier que les volumes sont correctement mappés dans le `docker-compose.yml` :

```yaml
volumes:
  - ${GITLAB_HOME}/data:/var/opt/gitlab
  - ${GITLAB_HOME}/logs:/var/log/gitlab
  - ${GITLAB_HOME}/config:/etc/gitlab
```

---

## Étape 3 : Créer les secrets (mot de passe root + mot de passe SMTP)

Il est recommandé de **ne pas versionner** les mots de passe. Créez les secrets Docker :

```bash
cd gitlab-ce
docker secret rm gitlab_root_password
openssl rand -base64 24 | tee ./docker/gitlab/root_password.txt | docker secret create gitlab_root_password -

# Mot de passe SMTP (fichier non versionné, cf. .gitignore)
echo "<mot-de-passe-smtp>" > ./docker/gitlab/smtp_password.txt
docker secret rm gitlab_smtp_password 2>/dev/null
docker secret create gitlab_smtp_password ./docker/gitlab/smtp_password.txt

# Token d'enregistrement des runners CI (fichier non versionné)
# À créer dans l'UI : Espace d'administration -> CI/CD -> Runners -> "Créer un runner d'instance"
echo "glrt-..." > ./docker/gitlab/runner_token.txt
docker secret rm gitlab_runner_token 2>/dev/null
docker secret create gitlab_runner_token ./docker/gitlab/runner_token.txt
```

> **Runners CI** : les replicas `gitlab-runner` (4 par défaut) s'enregistrent automatiquement au démarrage avec ce token (executor `docker`). La variable `GITLAB_HOST_IP` du `.env` doit contenir l'IP de la VM pour que les containers de job résolvent `GITLAB_HOSTNAME`. La configuration du runner est persistée dans le volume Swarm `gitlab_runner_config`.

> Le secret `gitlab_root_password` sera injecté dans GitLab au démarrage pour définir le mot de passe initial du compte `root`. Le secret `gitlab_smtp_password` est lu par `gitlab.rb` depuis `/run/secrets/gitlab_smtp_password`.
>
> Alternativement, `make create_secrets` crée les trois secrets automatiquement (fichiers requis : `smtp_password.txt` et `runner_token.txt` dans `docker/gitlab/`). Cette cible est **idempotente** : les secrets déjà existants sont conservés, ce qui permet de l'exécuter sans risque sur une instance en production.

---

## Étape 4 : Déployer la stack GitLab

Avec les volumes et les secrets prêts :

```bash
make deploy
```

Ou manuellement (après avoir exporté le `.env`, cf. ci-dessus) :

```bash
docker stack deploy -c docker-compose.yml gitlab
```

Cette commande :

* Crée les services `gitlab` (GitLab CE 19.2.0) et `gitlab-runner` (4 replicas)
* Monte les volumes persistants
* Injecte les secrets (root, SMTP, runner)
* Applique la configuration définie dans `gitlab.rb` (config Swarm versionnée par hash)

---

## Étape 5 : Vérification

* Vérifier les services :

```bash
docker service ls
docker service ps gitlab
```

* Vérifier les containers :

```bash
docker ps
```

* Vérifier les logs GitLab :

```bash
docker service logs gitlab
```

---

## Réinitialisation de l'instance GitLab

Si vous devez **réinitialiser complètement la configuration** :

1. Supprimer la stack :

```bash
docker stack rm gitlab
```

2. Supprimer les services et secrets existants :

```bash
docker config ls --format '{{.Name}}' | grep '^gitlab_conf_' | xargs -r docker config rm
docker secret rm gitlab_root_password 2>/dev/null
docker secret rm gitlab_smtp_password 2>/dev/null
docker secret rm gitlab_runner_token 2>/dev/null
```

3. Supprimer les containers résiduels (si nécessaire) :

```bash
docker rm -f $(docker ps -aq --filter "name=gitlab")
```

4. Créer à nouveau les secrets et vérifier les volumes persistants.
5. Déployer la stack avec `make deploy` (ou `docker stack deploy -c docker-compose.yml gitlab`).

---

## Notes importantes

* Les mots de passe et tokens doivent **toujours être gérés via Docker secrets** ou fichiers non versionnés (`.gitignore`).
* Les volumes persistants doivent être créés avec les permissions correctes (`chown -R 1000:1000`) pour permettre au conteneur GitLab de fonctionner correctement.
* L'`external_url` est configuré via **`GITLAB_EXTERNAL_URL`** dans le `.env` (pas de modification manuelle de `gitlab.rb` pour changer l'URL).
* Pour les **artefacts CI volumineux** (ex. installateurs Electron), augmenter la limite dans l'admin : **Paramètres → CI/CD → Taille maximale des artefacts** (défaut 100 Mo).
* **GitLab Pages** (optionnel) : décommenter `pages_external_url` et `gitlab_pages['namespace_in_path']` dans `docker/gitlab/gitlab.rb`, puis `make deploy`.

---

## Flux fonctionnel (Mermaid)

### 1. Déploiement initial

```mermaid
flowchart TD
    A[Admin DevOps] --> B[Copier .env.example vers .env]
    B --> C[Configurer GITLAB_HOME<br/>GITLAB_EXTERNAL_URL<br/>GITLAB_HOSTNAME<br/>GITLAB_HOST_IP<br/>SMTP_*]
    C --> D[Créer fichiers locaux non versionnés]
    D --> D1[docker/gitlab/smtp_password.txt]
    D --> D2[docker/gitlab/runner_token.txt<br/>token glrt- depuis UI Admin]
    D1 --> E[make create_secrets]
    D2 --> E
    E --> E1[Secret gitlab_root_password<br/>généré aléatoirement]
    E --> E2[Secret gitlab_smtp_password]
    E --> E3[Secret gitlab_runner_token]
    E1 --> F[make deploy]
    E2 --> F
    E3 --> F
    F --> G[Makefile charge .env et exporte les variables]
    G --> H[docker stack deploy]
    H --> I[Config Swarm gitlab_conf_HASH<br/>depuis docker/gitlab/gitlab.rb]
    H --> J[Service gitlab x1]
    H --> K[Service gitlab-runner x4]
    K --> L{config.toml existe ?}
    L -->|Non| M[gitlab-runner register<br/>URL = GITLAB_EXTERNAL_URL]
    L -->|Oui| N[Reprendre config persistée]
    M --> O[Runners en ligne dans Admin CI/CD]
    N --> O
    J --> P[GitLab CE accessible<br/>GITLAB_EXTERNAL_URL]
```

### 2. Architecture runtime

```mermaid
flowchart LR
    subgraph Host["VM hôte (Docker Swarm)"]
        subgraph Swarm["Stack gitlab"]
            subgraph Net["Réseau overlay gitlab-network"]
                GL[gitlab<br/>CE 19.2.0<br/>hostname: GITLAB_HOSTNAME]
                R1[gitlab-runner<br/>replica 1]
                R2[gitlab-runner<br/>replica 2]
                R3[gitlab-runner<br/>replica 3]
                R4[gitlab-runner<br/>replica 4]
            end
            subgraph VolHost["Volumes persistants hôte"]
                VDATA["/data/gitlab/data"]
                VLOGS["/data/gitlab/logs"]
                VCONF["/data/gitlab/config"]
                VCERTS["/data/gitlab/certs"]
            end
            subgraph VolSwarm["Volumes Swarm"]
                VRUN["gitlab_runner_config<br/>/etc/gitlab-runner"]
            end
            subgraph Secrets["Docker secrets"]
                S1[gitlab_root_password]
                S2[gitlab_smtp_password]
                S3[gitlab_runner_token]
            end
            subgraph Config["Docker config"]
                C1["gitlab_conf_HASH<br/>→ /omnibus_config.rb"]
            end
        end
        SOCK["/var/run/docker.sock"]
        subgraph JobContainers["Containers de job CI<br/>hors overlay Swarm"]
            JOB[Job container<br/>executor docker]
        end
    end

    DEV[Utilisateur / navigateur] -->|80 443 2222| GL
    GL --- VDATA
    GL --- VLOGS
    GL --- VCONF
    C1 -.-> GL
    S1 -.-> GL
    S2 -.-> GL
    GL -.->|alias réseau| R1
    GL -.->|alias réseau| R2
    GL -.->|alias réseau| R3
    GL -.->|alias réseau| R4
    S3 -.-> R1
    S3 -.-> R2
    S3 -.-> R3
    S3 -.-> R4
    VRUN --- R1
    VRUN --- R2
    VRUN --- R3
    VRUN --- R4
    R1 --- SOCK
    R2 --- SOCK
    R3 --- SOCK
    R4 --- SOCK
    SOCK --> JOB
    JOB -.->|extra-hosts<br/>GITLAB_HOSTNAME:GITLAB_HOST_IP| GL
    SMTP[Serveur SMTP] -.->|port 587| GL
```

### 3. Exécution d'un job CI/CD

```mermaid
sequenceDiagram
    actor Dev as Développeur
    participant GL as GitLab CE
    participant Runner as gitlab-runner
    participant Job as Container de job
    participant API as API GitLab<br/>GITLAB_EXTERNAL_URL

    Dev->>GL: Push / tag / pipeline déclenché
    GL->>GL: Planifie les jobs du .gitlab-ci.yml
    GL->>Runner: Assigne un job (via réseau overlay)
    Runner->>Job: docker run (socket hôte)<br/>extra-hosts GITLAB_HOSTNAME → GITLAB_HOST_IP
  Job->>API: git clone / fetch du dépôt
    Job->>Job: Exécute script (build, test…)
    Job->>API: Upload artefacts (POST /api/v4/jobs/…/artifacts)
    Job-->>Runner: Exit code
    Runner-->>GL: Rapport de fin de job
    GL-->>Dev: Pipeline vert / rouge dans l'UI
```

### 4. Configuration injectée

```mermaid
flowchart TB
    ENV[".env<br/>GITLAB_EXTERNAL_URL<br/>GITLAB_HOSTNAME<br/>GITLAB_HOST_IP<br/>SMTP_*"] --> MAKE[Makefile<br/>include + export]
    MAKE --> COMPOSE[docker-compose.yml]
    COMPOSE --> GLENV[Variables env container gitlab]
    COMPOSE --> RENV[Variables env container runner]
    RB["docker/gitlab/gitlab.rb"] --> HASH[Hash MD5 → gitlab_conf_HASH]
    HASH --> SWCFG[Config Swarm immuable]
    SWCFG --> OMNIBUS["/omnibus_config.rb<br/>dans le container"]
    GLENV --> OMNIBUS
    OMNIBUS --> RUBY["gitlab.rb Ruby<br/>external_url ENV fetch<br/>SMTP ENV + secrets"]
    RUBY --> OMN["gitlab-ctl reconfigure<br/>Nginx, Rails, Sidekiq…"]
```

> Les diagrammes ci-dessus décrivent le flux de déploiement, l'architecture Swarm, l'exécution CI/CD et l'injection de configuration pour l'instance GitLab CE Seris.

---

> Ce guide est destiné à l'équipe DevOps de **Seris** pour déployer et gérer GitLab de manière sécurisée et reproductible dans un environnement Docker Swarm.
