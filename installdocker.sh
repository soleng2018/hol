#!/bin/bash

set -euo pipefail

trap 'echo "❌ An error occurred. You may need to run: sudo dpkg --configure -a && sudo apt-get install -f"' ERR

# Helper: Check if current user is in docker group
in_docker_group() {
    groups "$USER" | grep -qw docker
}

# INSTALL FUNCTIONS ---------------------------------------------------

check_docker_installed() {
    if command -v docker &> /dev/null; then
        echo "✅ Docker is already installed."
        return 0
    else
        echo "🔍 Docker not found. Proceeding with installation..."
        return 1
    fi
}

install_docker() {
    echo "📦 Installing Docker..."

    sudo apt-get update
    sudo apt-get install -f -y || true
    sudo dpkg --configure -a || true

    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "✅ Docker installed successfully."
}

configure_docker_permissions() {
    if in_docker_group; then
        echo "✅ User '$USER' is already in the docker group."
    else
        echo "👥 Adding user '$USER' to docker group..."
        sudo usermod -aG docker "$USER"
        newgrp docker
        echo "✅ $USER added to docker group"
    fi
}

# REMOVE FUNCTIONS ---------------------------------------------------

remove_docker() {
    echo "🛑 This will remove Docker and all its data."

    read -rp "Are you sure you want to continue? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Aborted."
        exit 0
    fi

    echo "🧹 Stopping Docker services..."
    sudo systemctl stop docker || true
    sudo systemctl stop containerd || true

    echo "📦 Removing Docker packages..."
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

    sudo apt-get autoremove -y

    echo "🗑️ Deleting Docker files..."
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.gpg

    echo "👥 Removing user from docker group (if exists)..."
    if getent group docker &>/dev/null; then
        sudo gpasswd -d "$USER" docker || true
        sudo groupdel docker || true
    fi

    echo "✅ Docker has been completely removed."
}

# MENU ---------------------------------------------------

show_menu() {
    echo ""
    echo "========== Docker Setup Script =========="
    echo "1) Install Docker"
    echo "2) Remove Docker"
    echo "q) Quit"
    echo "========================================="
    echo ""
}

# MAIN ---------------------------------------------------

main() {
    show_menu
    read -rp "Choose an option [1/2/q]: " choice

    case "$choice" in
        1)
            check_docker_installed || install_docker
            configure_docker_permissions
            ;;
        2)
            remove_docker
            ;;
        q|Q)
            echo "👋 Bye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid choice. Try again."
            main
            ;;
    esac
}

main
