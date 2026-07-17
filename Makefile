# Makefile pour automatiser le déploiement de GitLab CE en Docker Swarm

# Charge les variables du fichier .env et les exporte vers les commandes
# (docker stack deploy ne lit pas le .env automatiquement)
include .env
export

# Vérifie que la variable GITLAB_HOME est définie
ifeq ($(origin GITLAB_HOME),undefined)
$(error La variable GITLAB_HOME n'est pas définie. Ajoutez-la au fichier .env, par exemple : GITLAB_HOME=/data/gitlab)
endif

# Variables
COMPOSE_FILE=docker-compose.yml
STACK_NAME=gitlab
SMTP_PASSWORD_FILE=docker/gitlab/smtp_password.txt

.PHONY: all init_volumes create_secrets deploy reinit status

all:
	@echo "GITLAB_HOME est défini sur $(GITLAB_HOME)"
	$(MAKE) init_volumes create_secrets deploy

## Étape 1 : Préparer les répertoires persistants
init_volumes:
	@echo "Création des répertoires persistants pour GitLab..."
	sudo mkdir -p $(GITLAB_HOME)/data $(GITLAB_HOME)/logs $(GITLAB_HOME)/config $(GITLAB_HOME)/ssl
	sudo chown -R 1000:1000 $(GITLAB_HOME)
	@echo "Répertoires créés et permissions définies."

## Étape 2 : Créer les secrets Docker (mot de passe root + mot de passe SMTP)
create_secrets:
	@echo "Création du secret Docker pour le mot de passe root..."
	@docker secret rm gitlab_root_password 2>/dev/null || true
	@openssl rand -base64 24 | docker secret create gitlab_root_password -
	@echo "Création du secret Docker pour le mot de passe SMTP..."
	@test -f $(SMTP_PASSWORD_FILE) || { echo "Erreur : $(SMTP_PASSWORD_FILE) introuvable. Créez ce fichier avec le mot de passe SMTP."; exit 1; }
	@docker secret rm gitlab_smtp_password 2>/dev/null || true
	@docker secret create gitlab_smtp_password $(SMTP_PASSWORD_FILE)
	@echo "Secrets créés."

## Étape 3 : Déployer la stack GitLab
deploy:
	@echo "Déploiement de la stack GitLab..."
	docker stack deploy -c $(COMPOSE_FILE) $(STACK_NAME)
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
