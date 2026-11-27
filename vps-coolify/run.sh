#!/bin/sh
# Coolify (self-hosted PaaS on Docker + Traefik) through its official installer. Env vars: see README.

set -eu
export DEBIAN_FRONTEND=noninteractive
zz-use zz-colors zz-log zz-install zz-step
# shellcheck disable=SC1091
. zz-colors

COOLIFY_INSTALL_URL=https://cdn.coollabs.io/coolify/install.sh

# The app and its proxy must both exist: an app without proxy is a broken install, which re-running the installer repairs.
is_coolify_installed() {
    command -v docker >/dev/null 2>&1 && docker container inspect coolify >/dev/null 2>&1 &&
        docker container inspect coolify-proxy >/dev/null 2>&1
}

up() {
    local ui_port

    ui_port="$(vps-network port system_coolify_ui)"

    if is_coolify_installed; then
        zz-log i "Coolify already installed; not re-running its installer (upgrade from the Coolify UI)."
    else
        # k3s's ServiceLB holds 80/443 with iptables rules the proxy's own port check cannot see.
        if command -v k3s >/dev/null 2>&1; then
            zz-log e "k3s is installed and its Traefik owns ports 80/443, which Coolify's proxy needs too." \
                "Run one ingress: sudo vps-setup --down-app-rancher --down-svc-k3s --with-vps-coolify" && exit 1
        fi
        if [ -d /etc/dokploy ]; then
            zz-log e "Dokploy is installed and its Traefik owns ports 80/443, which Coolify's proxy needs too." \
                "Run one PaaS: sudo vps-setup --down-vps-dokploy --with-vps-coolify" && exit 1
        fi
        # Upstream variable names: the installer reads them from its environment.
        export ROOT_USERNAME="${SYSTEM_COOLIFY_ROOT_USERNAME:-}" ROOT_USER_EMAIL="${SYSTEM_COOLIFY_ROOT_EMAIL:-}"
        export ROOT_USER_PASSWORD="${SYSTEM_COOLIFY_ROOT_PASSWORD:-}"
        export DOCKER_ADDRESS_POOL_BASE="${SYSTEM_COOLIFY_DOCKER_ADDRESS_POOL_BASE:-}"
        zz-log i "Running the Coolify installer; it installs Docker if needed..."
        # The official installer needs bash.
        zz-install -u "$COOLIFY_INSTALL_URL" -x bash coolify
        is_coolify_installed || { zz-log e "The Coolify installer finished but the coolify containers are not there." && exit 1; }
    fi

    # Docker publishes the admin UI past ufw: vps-security's FORWARD guard covers it.
    vps-network reapply-guard
    zz-log s "Coolify installed. Admin UI on port ${ui_port}, private access only (the first visit creates the admin account)."
}

down() {
    if command -v docker >/dev/null 2>&1; then
        zz-log i "Removing Coolify and the applications it deployed..."
        # Everything Coolify deploys carries its label; remove those first, then its own stack.
        docker ps -aq --filter label=coolify.managed=true | xargs -r docker rm -f 2>/dev/null || true
        docker container rm -f coolify coolify-db coolify-redis coolify-realtime coolify-proxy coolify-sentinel 2>/dev/null || true
        # A kept db volume would not match the password a reinstall generates.
        docker volume ls -q --filter name=coolify | xargs -r docker volume rm -f 2>/dev/null || true
        docker network rm coolify 2>/dev/null || true
    else
        zz-log w "Docker not found; nothing to remove besides /data/coolify."
    fi
    rm -rf /data/coolify
    if command -v docker >/dev/null 2>&1; then
        zz-log i "Removing Docker (the Coolify installer installed it)..."
        systemctl disable --now docker docker.socket containerd 2>/dev/null || true
        apt-mark unhold docker-ce docker-ce-cli docker-ce-rootless-extras 2>/dev/null || true
        zz-install -r docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin containerd.io docker.io || true
    fi
    zz-log s "Coolify removed."
}

summary() {
    # Opt-in step: say nothing on a host that never installed it.
    [ -d /data/coolify ] || return 0
    vps-network summary-block Coolify \
        "apps served by Coolify's own proxy on 80/443" - \
        "http://localhost:$(vps-network port system_coolify_ui) (admin UI, on the VPS; also http://$(vps-network summary-host):$(vps-network port system_coolify_ui) on the internal address)" \
        "The first visit creates the admin account: join the internal network first."
}

. zz-step
