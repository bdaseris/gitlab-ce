## Settings for GitLab instance

# URL complète (ex. http://gitlab.local) — injectée via docker-compose environment
external_url ENV.fetch('GITLAB_EXTERNAL_URL')

# SSH settings
gitlab_rails['gitlab_shell_ssh_port'] = 2222

# Nginx settings
gitlab_rails['nginx'] = {
  'redirect_http_to_https' => true,
  'ssl_certificate' => "/data/gitlab/certs/gitlab.securit.fr.crt",
  'ssl_certificate_key' => "/data/gitlab/certs/gitlab.securit.fr.key",
  'client_max_body_size' => '1g'
}

## GitLab Pages (publication des artefacts, ex. mises à jour electron-updater)
# Décommenter pages_external_url pour activer Pages (sinon laisser commenté).
# namespace_in_path évite le besoin d'un DNS wildcard :
#   http://pages.gitlab.local/<namespace>/<projet>
# pages_external_url 'http://pages.gitlab.local'
# gitlab_pages['namespace_in_path'] = true

# Initial root password from Docker secret
gitlab_rails['initial_root_password'] = File.read('/run/secrets/gitlab_root_password').gsub("\n", "")

## Email settings (envoi SMTP uniquement)
# Les valeurs non sensibles proviennent des variables d'environnement (.env),
# le mot de passe provient du Docker secret gitlab_smtp_password.
# incoming_email reste désactivé : il nécessite une boîte IMAP dédiée,
# sinon le service mail_room crash en boucle.
gitlab_rails['incoming_email_enabled'] = false
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = ENV['SMTP_ADDRESS']
gitlab_rails['smtp_port'] = ENV['SMTP_PORT'].to_i
gitlab_rails['smtp_user_name'] = ENV['SMTP_USER_NAME']
gitlab_rails['smtp_password'] = File.read('/run/secrets/gitlab_smtp_password').gsub("\n", "")
gitlab_rails['smtp_domain'] = ENV['SMTP_DOMAIN']
gitlab_rails['smtp_enable_starttls_auto'] = true
