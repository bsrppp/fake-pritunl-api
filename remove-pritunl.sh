#!/bin/bash
#
# remove-pritunl.sh - Complete Pritunl removal script
# Covers: packages, services, MongoDB, OpenVPN, configs, data, apt repo, systemd units
#

set -u
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
    err "Root privileges required. Run: sudo bash $0"
    exit 1
fi

warn "=========================================================="
warn "  THIS WILL COMPLETELY REMOVE PRITUNL AND ALL ITS DATA"
warn "  INCLUDING MongoDB, OpenVPN configs, and all VPN data."
warn "  This action is IRREVERSIBLE."
warn "=========================================================="
read -rp "Type 'YES' to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    err "Aborted by user."
    exit 1
fi

# ------------------------------------------------------------------
# 1. Stop and disable services
# ------------------------------------------------------------------
log "Stopping and disabling services..."
for svc in pritunl pritunl-web mongod mongodb openvpn openvpn@server; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
        systemctl stop "${svc}.service" 2>/dev/null || true
        systemctl disable "${svc}.service" 2>/dev/null || true
        log "  stopped/disabled: ${svc}"
    fi
done

# Kill any leftover processes
log "Killing leftover processes..."
pkill -9 -f pritunl 2>/dev/null || true
pkill -9 -f mongod  2>/dev/null || true

# ------------------------------------------------------------------
# 2. Remove packages (Debian/Ubuntu)
# ------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    log "Purging Pritunl / MongoDB / OpenVPN packages (apt)..."
    apt-get --purge autoremove -y pritunl pritunl-* 2>/dev/null || true
    apt-get --purge autoremove -y 'mongo*' 2>/dev/null || true
    apt-get --purge autoremove -y 'mongodb*' 2>/dev/null || true
    apt-get --purge autoremove -y openvpn 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 3. Remove packages (RHEL/CentOS/Fedora)
# ------------------------------------------------------------------
if command -v yum >/dev/null 2>&1; then
    log "Purging Pritunl / MongoDB / OpenVPN packages (yum)..."
    yum remove -y pritunl pritunl-* mongo* mongodb* openvpn 2>/dev/null || true
fi
if command -v dnf >/dev/null 2>&1; then
    log "Purging Pritunl / MongoDB / OpenVPN packages (dnf)..."
    dnf remove -y pritunl pritunl-* mongo* mongodb* openvpn 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 4. Remove config and data directories
# ------------------------------------------------------------------
log "Removing config and data directories..."
DIRS=(
    /etc/pritunl
    /var/lib/pritunl
    /var/log/pritunl
    /usr/lib/pritunl
    /usr/share/pritunl
    /opt/pritunl
    /etc/mongod.conf
    /etc/mongodb.conf
    /var/lib/mongodb
    /var/log/mongodb
    /var/run/mongodb
    /etc/openvpn
    /var/log/openvpn
    /run/pritunl
)
for d in "${DIRS[@]}"; do
    if [[ -e "$d" ]]; then
        rm -rf "$d"
        log "  removed: $d"
    fi
done

# ------------------------------------------------------------------
# 5. Remove systemd unit files that may remain
# ------------------------------------------------------------------
log "Removing leftover systemd unit files..."
for unit in \
    /etc/systemd/system/pritunl.service \
    /lib/systemd/system/pritunl.service \
    /usr/lib/systemd/system/pritunl.service \
    /etc/systemd/system/mongod.service \
    /lib/systemd/system/mongod.service \
    /usr/lib/systemd/system/mongod.service \
    /etc/systemd/system/openvpn@.service \
    /lib/systemd/system/openvpn@.service
do
    if [[ -f "$unit" ]]; then
        rm -f "$unit"
        log "  removed: $unit"
    fi
done
systemctl daemon-reload 2>/dev/null || true

# ------------------------------------------------------------------
# 6. Remove apt repo and GPG keys
# ------------------------------------------------------------------
log "Removing apt repository entries and GPG keys..."
rm -f /etc/apt/sources.list.d/pritunl.list
rm -f /etc/apt/sources.list.d/mongodb*.list
rm -f /etc/apt/trusted.gpg.d/pritunl.gpg
rm -f /usr/share/keyrings/pritunl.gpg
rm -f /etc/apt/trusted.gpg.d/mongodb*.gpg
rm -f /usr/share/keyrings/mongodb*.gpg
if command -v apt-key >/dev/null 2>&1; then
    apt-key list 2>/dev/null | grep -iE 'pritunl|mongodb' -B1 | grep -oE '[0-9A-F]{40}' | while read -r key; do
        apt-key del "$key" 2>/dev/null || true
    done
fi

# ------------------------------------------------------------------
# 7. Remove yum/dnf repo files
# ------------------------------------------------------------------
rm -f /etc/yum.repos.d/pritunl.repo
rm -f /etc/yum.repos.d/mongodb*.repo

# ------------------------------------------------------------------
# 8. Remove leftover python site-packages references
# ------------------------------------------------------------------
log "Cleaning Python site-packages leftovers..."
for py in /usr/lib/python3*/site-packages /usr/lib/python3/dist-packages; do
    [[ -d "$py" ]] || continue
    find "$py" -maxdepth 1 -type d \( -iname 'pritunl*' -o -iname 'pymongo*' -o -iname 'gridfs*' -o -iname 'bson*' \) -exec rm -rf {} + 2>/dev/null || true
done

# ------------------------------------------------------------------
# 9. Refresh apt cache if apt is present
# ------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    log "Refreshing apt cache..."
    apt-get update -y 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 10. Final verification
# ------------------------------------------------------------------
log "Verifying removal..."
echo
echo "--- dpkg packages ---"
dpkg -l 2>/dev/null | grep -iE 'pritunl|mongo' || echo "  (none)"
echo "--- rpm packages ---"
rpm -qa 2>/dev/null | grep -iE 'pritunl|mongo' || echo "  (none)"
echo "--- running processes ---"
ps aux | grep -E 'pritunl|mongod' | grep -v grep || echo "  (none)"
echo "--- leftover directories ---"
for d in /etc/pritunl /var/lib/pritunl /var/log/pritunl /usr/lib/pritunl \
         /etc/openvpn /var/lib/mongodb /var/log/mongodb; do
    [[ -e "$d" ]] && echo "  STILL EXISTS: $d"
done
echo "  (directory check done)"
echo "--- apt sources ---"
ls /etc/apt/sources.list.d/ 2>/dev/null | grep -iE 'pritunl|mongo' || echo "  (none)"
echo

log "Removal complete. If anything still appears above, remove it manually."
log "Recommended: reboot the server to ensure no kernel modules / mounts remain."