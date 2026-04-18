#!/bin/bash
# ============================================================
#  NUCLEAR CLEAN SCRIPT — prodxcloud / @chiefairesearcher
#  FULLY AUTOMATED — ZERO PROMPTS — NO HUMAN IN LOOP
#  Ubuntu / Debian / any systemd Linux (EC2-safe)
#  SSH keys & networking ALWAYS preserved.
#  Run: sudo bash clean.sh 1111
# ============================================================

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Must run as root: sudo bash clean.sh"
  exit 1
fi

LOG="/var/log/nuclear-clean-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

OK()   { echo "  [OK] $1"; }
INFO() { echo "  [>>] $1"; }
WARN() { echo "  [!!] $1"; }

DISK_BEFORE=$(df / --output=avail -h | tail -1 | xargs)

echo "============================================================"
echo "  NUCLEAR CLEAN — $(date)"
echo "  Host: $(hostname)"
echo "  OS:   $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "  Disk before: $DISK_BEFORE"
echo "  Log:  $LOG"
echo "============================================================"

# ════════════════════════════════════════════════════════════
#  1. DOCKER
# ════════════════════════════════════════════════════════════
echo; echo "==> [1/11] DOCKER"

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  CONTAINERS=$(docker ps -aq 2>/dev/null || true)
  if [[ -n "$CONTAINERS" ]]; then
    docker stop $CONTAINERS 2>/dev/null   || WARN "Some containers failed to stop"
    docker rm -f $CONTAINERS 2>/dev/null  || WARN "Some containers failed to remove"
    OK "All containers stopped and removed"
  else
    OK "No containers found"
  fi

  IMAGES=$(docker images -aq 2>/dev/null || true)
  if [[ -n "$IMAGES" ]]; then
    docker rmi -f $IMAGES 2>/dev/null || WARN "Some images could not be removed"
    OK "All images removed"
  else
    OK "No images found"
  fi

  VOLS=$(docker volume ls -q 2>/dev/null || true)
  if [[ -n "$VOLS" ]]; then
    docker volume rm $VOLS 2>/dev/null || WARN "Some volumes could not be removed"
    OK "All volumes removed"
  else
    OK "No volumes found"
  fi

  docker network prune -f 2>/dev/null && OK "Custom networks pruned" || true
  docker system prune -a --volumes -f 2>/dev/null && OK "docker system prune -a done" || true
  find /var/lib/docker/containers -name "*.log" -type f \
    -exec truncate -s 0 {} \; 2>/dev/null && OK "Container log files truncated" || true

  systemctl stop docker docker.socket containerd 2>/dev/null || true
  systemctl disable docker docker.socket containerd 2>/dev/null || true

  DEBIAN_FRONTEND=noninteractive apt-get purge -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    docker.io docker-doc docker-compose \
    podman-docker 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>/dev/null || true

  rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  rm -f /usr/local/bin/docker-compose /usr/bin/docker /usr/local/bin/docker
  OK "Docker fully uninstalled and data removed"
else
  WARN "Docker not running — cleaning leftover dirs"
  rm -rf /var/lib/docker /var/lib/containerd /etc/docker 2>/dev/null || true
  OK "Docker directories removed"
fi

# ════════════════════════════════════════════════════════════
#  2. TERRAFORM
# ════════════════════════════════════════════════════════════
echo; echo "==> [2/11] TERRAFORM"

find /home /root /opt /srv /var/www /tmp -maxdepth 8 \
  \( -name ".terraform" \
     -o -name ".terraform.lock.hcl" \
     -o -name "terraform.tfstate" \
     -o -name "terraform.tfstate.backup" \
     -o -name "tfplan" \
     -o -name "*.tfplan" \) \
  -exec rm -rf {} + 2>/dev/null || true
OK "Terraform project artifacts removed"

rm -rf /root/.terraform.d 2>/dev/null || true
find /home -maxdepth 3 -name ".terraform.d" -type d -exec rm -rf {} + 2>/dev/null || true
OK "Terraform plugin caches removed"

TF_BIN=$(command -v terraform 2>/dev/null || true)
if [[ -n "$TF_BIN" ]]; then
  rm -f "$TF_BIN"
  OK "Terraform binary removed ($TF_BIN)"
else
  OK "No Terraform binary found"
fi

# ════════════════════════════════════════════════════════════
#  3. KUBERNETES / KUBECTL / HELM / K9S
# ════════════════════════════════════════════════════════════
echo; echo "==> [3/11] KUBERNETES TOOLING"

if command -v kubeadm &>/dev/null; then
  kubeadm reset -f 2>/dev/null && OK "kubeadm reset done" || WARN "kubeadm reset failed"
fi

rm -rf /root/.kube /root/.helm /root/.config/helm /root/.k9s 2>/dev/null || true
find /home -maxdepth 3 \
  \( -name ".kube" -o -name ".helm" -o -name ".k9s" \) \
  -type d -exec rm -rf {} + 2>/dev/null || true
find /home -maxdepth 4 -path "*/.config/helm" -type d -exec rm -rf {} + 2>/dev/null || true
OK "kubectl/helm/k9s configs removed"

for bin in kubectl helm k9s kubeadm kubelet kube-proxy; do
  BIN_PATH=$(command -v $bin 2>/dev/null || true)
  if [[ -n "$BIN_PATH" ]]; then
    rm -f "$BIN_PATH"
    OK "$bin binary removed"
  fi
done

# ════════════════════════════════════════════════════════════
#  4. SYSTEM LOGS
# ════════════════════════════════════════════════════════════
echo; echo "==> [4/11] SYSTEM LOGS"

if command -v journalctl &>/dev/null; then
  journalctl --rotate 2>/dev/null || true
  journalctl --vacuum-time=1s 2>/dev/null && OK "journald vacuumed" || true
fi

find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
find /var/log -type f \
  \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.3" \
     -o -name "*.4" -o -name "*.old" -o -name "*.bak" \
     -o -name "*.xz" -o -name "*.zst" \) \
  -delete 2>/dev/null || true

for f in /var/log/wtmp /var/log/btmp /var/log/lastlog \
          /var/log/syslog /var/log/kern.log /var/log/auth.log \
          /var/log/dpkg.log /var/log/apt/history.log /var/log/apt/term.log \
          /var/log/cloud-init.log /var/log/cloud-init-output.log \
          /var/log/unattended-upgrades/unattended-upgrades.log; do
  [[ -f "$f" ]] && truncate -s 0 "$f"
done
OK "All system logs wiped"

# ════════════════════════════════════════════════════════════
#  5. TMP, CACHE & BUILD ARTIFACTS
# ════════════════════════════════════════════════════════════
echo; echo "==> [5/11] TMP, CACHE & BUILD ARTIFACTS"

rm -rf /tmp/* /tmp/.[!.]* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null         || true
OK "/tmp and /var/tmp cleared"

DEBIAN_FRONTEND=noninteractive apt-get clean -y 2>/dev/null     || true
DEBIAN_FRONTEND=noninteractive apt-get autoclean -y 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>/dev/null || true
rm -rf /var/lib/apt/lists/*
OK "apt cache cleared"

pip3 cache purge 2>/dev/null || true
find /root /home -maxdepth 5 -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find /root /home -maxdepth 4 -type d \( -name ".cache" -o -name "*.egg-info" \) \
  -exec rm -rf {} + 2>/dev/null || true
OK "Python/pip caches cleared"

find /root /home /opt -maxdepth 6 -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
find /root /home -maxdepth 4 \( -name ".npm" -o -name ".yarn" \) \
  -type d -exec rm -rf {} + 2>/dev/null || true
OK "node_modules/npm/yarn caches cleared"

rm -rf /root/.cache/go-build /root/go/pkg 2>/dev/null || true
find /home -maxdepth 4 -path "*/.cache/go-build" -exec rm -rf {} + 2>/dev/null || true
OK "Go build cache cleared"

find /root /home -maxdepth 4 -name ".cargo" -type d -exec rm -rf {} + 2>/dev/null || true
OK "Cargo cache cleared"

find /root /home -maxdepth 4 \( -name ".m2" -o -name ".gradle" \) \
  -type d -exec rm -rf {} + 2>/dev/null || true
OK "Maven/Gradle caches cleared"

# ════════════════════════════════════════════════════════════
#  6. CLOUD-INIT RESET
# ════════════════════════════════════════════════════════════
echo; echo "==> [6/11] CLOUD-INIT RESET"

if command -v cloud-init &>/dev/null; then
  rm -rf /var/lib/cloud/instances/* /var/lib/cloud/data/* 2>/dev/null || true
  truncate -s 0 /var/log/cloud-init.log 2>/dev/null        || true
  truncate -s 0 /var/log/cloud-init-output.log 2>/dev/null || true
  OK "cloud-init state cleared (user-data will re-run on next boot)"
else
  OK "cloud-init not present"
fi

# ════════════════════════════════════════════════════════════
#  7. SHELL HISTORY
# ════════════════════════════════════════════════════════════
echo; echo "==> [7/11] SHELL HISTORY"

for hfile in /root/.bash_history /root/.zsh_history \
             /home/*/.bash_history /home/*/.zsh_history; do
  [[ -f "$hfile" ]] && truncate -s 0 "$hfile"
done
history -c 2>/dev/null || true
OK "Shell history cleared for all users"

# ════════════════════════════════════════════════════════════
#  8. SWAP
# ════════════════════════════════════════════════════════════
echo; echo "==> [8/11] SWAP"

if swapon --show | grep -q .; then
  SWAPFILE=$(swapon --show=NAME --noheadings 2>/dev/null | head -1 || true)
  swapoff -a && OK "Swap disabled"
  if [[ -n "$SWAPFILE" && -f "$SWAPFILE" ]]; then
    SIZE_MB=$(du -m "$SWAPFILE" | cut -f1)
    dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SIZE_MB" status=none 2>/dev/null || true
    mkswap "$SWAPFILE" 2>/dev/null && swapon "$SWAPFILE" \
      && OK "Swap wiped and re-enabled ($SWAPFILE)"
  fi
else
  OK "No swap found — skipped"
fi

# ════════════════════════════════════════════════════════════
#  9. HOME DIRECTORIES — SSH keys preserved
# ════════════════════════════════════════════════════════════
echo; echo "==> [9/11] HOME DIRECTORIES"

ALL_USERS=("root")
while IFS= read -r u; do ALL_USERS+=("$u"); done < <(ls /home 2>/dev/null)

for u in "${ALL_USERS[@]}"; do
  HOME_DIR=$( [[ "$u" == "root" ]] && echo /root || echo "/home/$u" )
  [[ -d "$HOME_DIR" ]] || continue

  AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
  KNOWN_HOSTS="$HOME_DIR/.ssh/known_hosts"
  ID_FILES=( "$HOME_DIR/.ssh/id_rsa" "$HOME_DIR/.ssh/id_rsa.pub"
             "$HOME_DIR/.ssh/id_ed25519" "$HOME_DIR/.ssh/id_ed25519.pub" )

  # Backup SSH artifacts
  SSHTMP=$(mktemp -d)
  [[ -f "$AUTH_KEYS"   ]] && cp "$AUTH_KEYS"   "$SSHTMP/authorized_keys"
  [[ -f "$KNOWN_HOSTS" ]] && cp "$KNOWN_HOSTS" "$SSHTMP/known_hosts"
  for f in "${ID_FILES[@]}"; do
    [[ -f "$f" ]] && cp "$f" "$SSHTMP/$(basename $f)"
  done

  # Wipe home
  find "$HOME_DIR" -mindepth 1 -maxdepth 1 ! -name ".ssh" -exec rm -rf {} + 2>/dev/null || true
  find "$HOME_DIR/.ssh" -mindepth 1 -maxdepth 1 \
    ! -name "authorized_keys" ! -name "known_hosts" \
    ! -name "id_rsa" ! -name "id_rsa.pub" \
    ! -name "id_ed25519" ! -name "id_ed25519.pub" \
    -exec rm -rf {} + 2>/dev/null || true

  # Restore SSH
  mkdir -p "$HOME_DIR/.ssh"
  [[ -f "$SSHTMP/authorized_keys" ]] && \
    cp "$SSHTMP/authorized_keys" "$AUTH_KEYS" && chmod 600 "$AUTH_KEYS"
  [[ -f "$SSHTMP/known_hosts" ]] && \
    cp "$SSHTMP/known_hosts" "$KNOWN_HOSTS" && chmod 644 "$KNOWN_HOSTS"
  for f in id_rsa id_rsa.pub id_ed25519 id_ed25519.pub; do
    [[ -f "$SSHTMP/$f" ]] && \
      cp "$SSHTMP/$f" "$HOME_DIR/.ssh/$f" && chmod 600 "$HOME_DIR/.ssh/$f"
  done
  chmod 700 "$HOME_DIR/.ssh" 2>/dev/null || true
  rm -rf "$SSHTMP"
  OK "Wiped $HOME_DIR — SSH keys preserved"
done

# ════════════════════════════════════════════════════════════
#  10. DEVOPS TOOL CONFIG & CREDENTIALS
# ════════════════════════════════════════════════════════════
echo; echo "==> [10/11] DEVOPS TOOL CONFIG & CREDENTIALS"

rm -rf /etc/ansible /root/.ansible 2>/dev/null || true
find /home -maxdepth 3 -name ".ansible" -type d -exec rm -rf {} + 2>/dev/null || true
OK "Ansible configs removed"

rm -rf /root/.aws 2>/dev/null || true
find /home -maxdepth 3 -name ".aws" -type d -exec rm -rf {} + 2>/dev/null || true
OK "AWS CLI credentials removed"

rm -rf /root/.azure 2>/dev/null || true
find /home -maxdepth 3 -name ".azure" -type d -exec rm -rf {} + 2>/dev/null || true
OK "Azure CLI config removed"

rm -rf /root/.config/gcloud 2>/dev/null || true
find /home -maxdepth 4 -path "*/.config/gcloud" -exec rm -rf {} + 2>/dev/null || true
OK "gcloud config removed"

find /root /home /tmp -maxdepth 5 -name "packer_cache" -type d \
  -exec rm -rf {} + 2>/dev/null || true
OK "Packer cache removed"

rm -f /root/.vault-token 2>/dev/null || true
find /home -maxdepth 3 -name ".vault-token" -delete 2>/dev/null || true
OK "Vault tokens removed"

systemctl reset-failed 2>/dev/null && OK "systemd failed units reset" || true

# ════════════════════════════════════════════════════════════
#  11. FINAL REPORT
# ════════════════════════════════════════════════════════════
echo; echo "==> [11/11] FINAL REPORT"

DISK_AFTER=$(df / --output=avail -h | tail -1 | xargs)

echo "------------------------------------------------------------"
echo "  Disk before : $DISK_BEFORE"
echo "  Disk after  : $DISK_AFTER"
echo "------------------------------------------------------------"
echo "  Top 10 dirs by size:"
du -sh /* 2>/dev/null | sort -rh | head -10 || true
echo "------------------------------------------------------------"
echo "  Docker    : $(command -v docker    &>/dev/null && echo present || echo removed)"
echo "  Terraform : $(command -v terraform &>/dev/null && echo present || echo removed)"
echo "  kubectl   : $(command -v kubectl   &>/dev/null && echo present || echo removed)"
echo "  Helm      : $(command -v helm      &>/dev/null && echo present || echo removed)"
echo "------------------------------------------------------------"
echo "  Log saved : $LOG"
echo "============================================================"
echo "  [OK] NUCLEAR CLEAN COMPLETE — system ready for provisioning"
echo "============================================================"