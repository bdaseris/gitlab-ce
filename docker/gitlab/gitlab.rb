## Settings for GitLab instance

external_url 'http://gitlab.local'
# external_url 'https://gitlab.securit.fr'

# SSH settings
gitlab_rails['gitlab_shell_ssh_port'] = 2222

# Nginx settings
nginx['redirect_http_to_https'] = true

# Initial root password from Docker secret
gitlab_rails['initial_root_password'] = File.read('/run/secrets/gitlab_root_password').gsub("\n", "")

nginx['ssl_certificate'] = "/etc/gitlab/ssl/gitlab.securit.fr.crt"
nginx['ssl_certificate_key'] = "/etc/gitlab/ssl/gitlab.securit.fr.key"