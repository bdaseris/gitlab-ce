# Makefile pour automatiser le déploiement de GitLab CE en Docker Swarm

# Charge les variables du fichier .env et les exporte vers les commandes
# (docker stack deploy ne lit pas le .env automatiquement)
include .env
export

# make lit les guillemets du .env littéralement (contrairement à bash) :
# on les retire pour que la valeur exportée soit propre
SMTP_USER_NAME := $(subst ",,$(SMTP_USER_NAME))

# Vérifie que les variables essentielles sont définies
ifeq ($(origin GITLAB_HOME),undefined)
$(error La variable GITLAB_HOME n'est pas définie. Ajoutez-la au fichier .env, par exemple : GITLAB_HOME=/data/gitlab)
endif
ifeq ($(origin GITLAB_EXTERNAL_URL),undefined)
$(error La variable GITLAB_EXTERNAL_URL n'est pas définie. Exemple : GITLAB_EXTERNAL_URL=http://gitlab.local)
endif
ifeq ($(origin GITLAB_HOSTNAME),undefined)
$(error La variable GITLAB_HOSTNAME n'est pas définie. Exemple : GITLAB_HOSTNAME=gitlab.local (sans http://))
endif

# Variables
COMPOSE_FILE=docker-compose.yml
STACK_NAME=gitlab
SMTP_PASSWORD_FILE=docker/gitlab/smtp_password.txt
RUNNER_TOKEN_FILE=docker/gitlab/runner_token.txt

# Les configs Swarm sont immuables : le nom de la config inclut le hash de
# gitlab.rb pour que chaque modification crée une nouvelle config au lieu
# d'essayer de mettre à jour l'ancienne (interdit par Swarm)
GITLAB_CONFIG_HASH := $(shell md5sum docker/gitlab/gitlab.rb | cut -c1-8)

.PHONY: all init_volumes create_secrets deploy reinit status help

help:
	@echo "GitLab CE — commandes Make disponibles"
	@echo ""
	@echo "  make help           Affiche cette aide"
	@echo "  make all            Installation complète (init_volumes + create_secrets + deploy)"
	@echo "  make init_volumes   Crée les répertoires persistants sous GITLAB_HOME"
	@echo "  make create_secrets Crée les secrets Docker (idempotent, ne modifie pas les existants)"
	@echo "  make deploy         Déploie ou met à jour la stack Swarm"
	@echo "  make status         Affiche l'état des services Swarm"
	@echo "  make reinit         Supprime la stack et relance make all (ATTENTION : données conservées)"
	@echo ""
	@echo "Prérequis : fichier .env (copier depuis .env.example) et Swarm initialisé (docker swarm init)"
	@echo "Fichiers locaux requis pour create_secrets : docker/gitlab/smtp_password.txt, docker/gitlab/runner_token.txt"

all:
	@echo "GITLAB_HOME est défini sur $(GITLAB_HOME)"
	$(MAKE) init_volumes create_secrets deploy

## Étape 1 : Préparer les répertoires persistants
init_volumes:
	@echo "Création des répertoires persistants pour GitLab..."
	sudo mkdir -p $(GITLAB_HOME)/data $(GITLAB_HOME)/logs $(GITLAB_HOME)/config $(GITLAB_HOME)/certs
	sudo chown -R 1000:1000 $(GITLAB_HOME)
	@echo "Répertoires créés et permissions définies."

## Étape 2 : Créer les secrets Docker s'ils n'existent pas encore
## (idempotent : ne touche pas aux secrets déjà présents/utilisés)
create_secrets:
	@if docker secret inspect gitlab_root_password >/dev/null 2>&1; then \
		echo "Secret gitlab_root_password déjà présent, conservé."; \
	else \
		echo "Création du secret gitlab_root_password (aléatoire)..."; \
		openssl rand -base64 24 | docker secret create gitlab_root_password - >/dev/null; \
		echo "Secret gitlab_root_password créé."; \
	fi
	@if docker secret inspect gitlab_smtp_password >/dev/null 2>&1; then \
		echo "Secret gitlab_smtp_password déjà présent, conservé."; \
	else \
		test -f $(SMTP_PASSWORD_FILE) || { echo "Erreur : $(SMTP_PASSWORD_FILE) introuvable. Créez ce fichier avec le mot de passe SMTP."; exit 1; }; \
		echo "Création du secret gitlab_smtp_password à partir de $(SMTP_PASSWORD_FILE)..."; \
		docker secret create gitlab_smtp_password $(SMTP_PASSWORD_FILE) >/dev/null; \
		echo "Secret gitlab_smtp_password créé (contenu du fichier, non généré)."; \
	fi
	@if docker secret inspect gitlab_runner_token >/dev/null 2>&1; then \
		echo "Secret gitlab_runner_token déjà présent, conservé."; \
	else \
		test -f $(RUNNER_TOKEN_FILE) || { echo "Erreur : $(RUNNER_TOKEN_FILE) introuvable. Créez un runner d'instance dans l'UI admin (Admin -> CI/CD -> Runners) et collez le token glrt-... dans ce fichier."; exit 1; }; \
		echo "Création du secret gitlab_runner_token à partir de $(RUNNER_TOKEN_FILE)..."; \
		docker secret create gitlab_runner_token $(RUNNER_TOKEN_FILE) >/dev/null; \
		echo "Secret gitlab_runner_token créé."; \
	fi
	@echo "Secrets prêts."

## Étape 3 : Déployer la stack GitLab
deploy:
	@echo "Déploiement de la stack GitLab (config gitlab_conf_$(GITLAB_CONFIG_HASH))..."
	docker stack deploy --detach=true -c $(COMPOSE_FILE) $(STACK_NAME)
	@echo "Nettoyage des anciennes configs (ignorées si encore utilisées)..."
	@docker config ls --format '{{.Name}}' | grep '^gitlab_conf_' | grep -v '$(GITLAB_CONFIG_HASH)' | xargs -r -n1 docker config rm >/dev/null 2>&1 || true
	@echo "Stack déployée."

## Réinitialiser l'instance GitLab (supprimer et redéployer)
reinit:
	@echo "Suppression de l'ancienne stack GitLab..."
	docker stack rm $(STACK_NAME)
	@sleep 5
	$(MAKE) all

status:
	docker stack ps $(STACK_NAME)
	docker service ls
