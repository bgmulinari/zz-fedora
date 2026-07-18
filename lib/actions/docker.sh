#!/usr/bin/env bash
set -Eeuo pipefail

# Docker Engine install and post-install custom actions.

install_docker() {
  log_progress "Removing conflicting Docker packages"
  run_cmd_as_root dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine || true
  if ! fedora_repo_enabled docker-ce; then
    log_progress "Adding Docker CE repository"
    run_cmd_as_root dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  log_progress "Installing Docker Engine packages"
  run_cmd_as_root dnf install -y docker-ce docker-buildx-plugin docker-compose-plugin
}

verify_docker() {
  rpm -q \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin >/dev/null 2>&1
}

configure_docker_post_install() {
  log_progress "Configuring Docker service and user group"
  run_cmd_as_root systemctl daemon-reload
  run_cmd_as_root systemctl enable --now docker
  if ! id -nG "$TARGET_USER" 2>/dev/null | grep -qw docker; then
    run_cmd_as_root usermod -aG docker "$TARGET_USER"
  fi
}

verify_docker_post_install() {
  systemctl is-enabled docker.service >/dev/null 2>&1 \
    && id -nG "$TARGET_USER" | grep -qw docker
}

register_action "docker" install_docker verify_docker
register_action "docker-post-install" configure_docker_post_install verify_docker_post_install
