#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[OK]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

error_handler() {
    local exit_code=$?
    print_error "Command '${BASH_COMMAND}' failed at line $LINENO"
    exit "$exit_code"
}
trap error_handler ERR

[[ "$(id -u)" -ne 0 ]] && { print_error "This script must be run as root"; exit 1; }

system_updates() {
    print_info "Updating system packages..."
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq
    elif command -v dnf &>/dev/null; then
        dnf upgrade -y
    elif command -v yum &>/dev/null; then
        yum upgrade -y
    elif command -v apk &>/dev/null; then
        apk upgrade
    else
        print_warning "Unsupported package manager. Skipping system updates."
        return 0
    fi
    print_success "System packages updated."
}

setup_swap() {
    print_info "Removing existing swap spaces..."
    
    # Disable all swap
    swapoff -a 2>/dev/null || true
    
    # Remove swap entries from fstab
    if grep -q "swap" /etc/fstab; then
        sed -i '/\bswap\b/d' /etc/fstab
    fi

    # Delete common swap files
    rm -f /swapfile /swap.img /mnt/swapfile
    
    local swap_size="2G"
    local swap_file="/swapfile"

    print_info "Creating fresh ${swap_size} swap file..."
    fallocate -l "$swap_size" "$swap_file" || dd if=/dev/zero of="$swap_file" bs=1M count=2048 status=progress
    chmod 600 "$swap_file"
    mkswap "$swap_file"
    swapon "$swap_file"

    if ! grep -q "^$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
    fi

    # Adjust swappiness for better server performance
    sysctl vm.swappiness=10 2>/dev/null || true
    cat > /etc/sysctl.d/99-swappiness.conf << 'EOF'
vm.swappiness=10
EOF
    
    print_success "Fresh ${swap_size} swap space created and configured permanently."
}

setup_time_sync() {
    print_info "Configuring time synchronization..."
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet systemd-timesyncd; then
            print_success "systemd-timesyncd is already running."
            return 0
        fi
        
        if command -v apt-get &>/dev/null; then
            apt-get install -y systemd-timesyncd
            systemctl enable --now systemd-timesyncd
        elif command -v dnf &>/dev/null; then
            dnf install -y chrony
            systemctl enable --now chronyd
        elif command -v yum &>/dev/null; then
            yum install -y chrony
            systemctl enable --now chronyd
        fi
    fi
    
    # Force sync
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true || true
    elif command -v chronyc &>/dev/null; then
        chronyc makestep || true
    fi
    
    print_success "Time synchronization configured."
}

system_tuning() {
    print_info "Applying system tuning (BBR, TFO, high-concurrency TCP)..."

    cat > /etc/sysctl.d/99-tuning.conf << 'EOF'
# BBR and FQ
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# TCP Fast Open
net.ipv4.tcp_fastopen=3

# TCP Keepalive Tuning (Aggressive for VPN stability)
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_probes=9
net.ipv4.tcp_keepalive_intvl=60

# Buffer Tuning (Optimized for long-distance RU-EU links)
net.ipv4.tcp_rmem=4096 131072 12582912
net.ipv4.tcp_wmem=4096 131072 12582912

# System-wide socket buffer limits (must be >= tcp_rmem/wmem max)
net.core.rmem_max=12582912
net.core.wmem_max=12582912
net.core.rmem_default=131072
net.core.wmem_default=131072

# Enable auto-tuning
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_moderate_rcvbuf=1
net.core.netdev_max_backlog=5000
EOF

sysctl -p /etc/sysctl.d/99-tuning.conf 2>/dev/null || true

cat > /etc/security/limits.d/99-nofile.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

print_success "System tuning applied (BBR, high-concurrency TCP, fd limits raised)."
}


ssh_hardening() {
    print_info "SSH Hardening..."
    local sshd_cfg="/etc/ssh/sshd_config"
    local override_cfg="/etc/ssh/sshd_config.d/99-vpn-hardening.conf"

    read -rp "Enter your SSH public key (leave empty to skip SSH hardening): " ssh_key
    if [[ -z "$ssh_key" ]]; then
        print_warning "No SSH key provided — skipping SSH hardening"
        return 0
    fi

    # 1. Install the Key safely
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    # Idempotent append: only add if not already present
    if ! grep -qF "$ssh_key" /root/.ssh/authorized_keys 2>/dev/null; then
        echo -e "\n$ssh_key" >> /root/.ssh/authorized_keys
    fi
    chmod 600 /root/.ssh/authorized_keys
    print_success "SSH public key installed"

    # 2. Apply Hardening via high-priority override (handles Include bug)
    mkdir -p /etc/ssh/sshd_config.d/
    cat > "$override_cfg" << EOF
# VPN Setup Hardening - High Priority
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
EOF

    # 3. Clean up the main config to avoid duplicates and ensure Include is active
    sed -i 's/^#\?PermitRootLogin.*/# Removed by VPN script - see 99-vpn-hardening.conf/' "$sshd_cfg"
    sed -i 's/^#\?PasswordAuthentication.*/# Removed by VPN script - see 99-vpn-hardening.conf/' "$sshd_cfg"

    if sshd -t; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        print_success "SSH hardened (key-only auth forced)"
    else
        print_error "SSH config check failed! Reverting changes..."
        rm -f "$override_cfg"
        return 1
    fi
}

main() {
    echo -e ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  System Pre-Setup (Tuning & Hardening)     ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo -e ""
    echo -e "This script will:"
    echo -e "  1. Update system packages"
    echo -e "  2. Create 2GB swap space (if not exists)"
    echo -e "  3. Configure time synchronization"
    echo -e "  4. Apply system tuning (BBR, TFO, disable IPv6)"
    echo -e "  5. Optionally harden SSH"
    echo -e "  6. Prompt to reboot the system"
    echo -e ""

    read -rp "Continue? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        print_info "Aborted."
        exit 0
    fi

    system_updates
    setup_swap
    setup_time_sync
    system_tuning
    ssh_hardening

    echo -e ""
    print_success "Pre-setup completed successfully."
    echo -e "${YELLOW}A system reboot is recommended to fully apply system updates and kernel tuning.${NC}"
    read -rp "Reboot now? [y/N]: " reboot_confirm
    if [[ "${reboot_confirm,,}" == "y" ]]; then
        print_info "Rebooting system..."
        reboot
    else
        print_info "Reboot skipped. Please reboot later."
    fi
}

main "$@"