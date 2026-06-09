#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
set -Ee -o pipefail
# Copyright (c) 2026 Alessandro De Mitri
# Author: Alessandro De Mitri
# License: MIT
# Source: https://www.palworldgame.com/ | https://linuxgsm.com/servers/pwserver/

APP="Palworld"
var_tags="${var_tags:-game;steam;palworld;linuxgsm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-40}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_hostname="${var_hostname:-palworld}"
PWSERVER_PASSWORD=""
PWSERVER_PASSWORD_GENERATED="0"
PALWORLD_SERVER_NAME="Palworld Server"

# Local visual identity overrides. build.func remains the technical framework;
# this wrapper only rewrites visible whiptail branding strings at runtime.
whiptail() {
  local rewritten=()
  local arg

  for arg in "$@"; do
    arg="${arg//Proxmox VE Helper Scripts/Palworld Server Autoscript}"
    arg="${arg//Community-Scripts Options/Palworld Installer Options}"
    rewritten+=("$arg")
  done

  command whiptail "${rewritten[@]}"
}

header_info() {
  if command -v clear >/dev/null 2>&1; then
    clear 2>/dev/null || true
  fi
  cat <<'HEADER'
  ____   _    _     __        _____  ____  _     ____
 |  _ \ / \  | |    \ \      / / _ \|  _ \| |   |  _ \
 | |_) / _ \ | |     \ \ /\ / / | | | |_) | |   | | | |
 |  __/ ___ \| |___   \ V  V /| |_| |  _ <| |___| |_| |
 |_| /_/   \_\_____|   \_/\_/  \___/|_| \_\_____|____/

             PALWORLD
        LinuxGSM LXC Installer

        Palworld Server Autoscript
HEADER
}

generate_pwserver_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '/+=[:space:]' | cut -c1-24
    return 0
  fi

  LC_ALL=C tr -dc 'A-Za-z0-9_@%.,-' </dev/urandom | head -c 24
}

prompt_pwserver_password() {
  local password=""

  if type -P whiptail >/dev/null 2>&1; then
    password=$(whiptail --title "Palworld User Password" --passwordbox 'Set password for LinuxGSM user "pwserver". Leave blank to generate a secure random password.' 10 78 3>&1 1>&2 2>&3) || exit 1
  else
    read -r -s -p 'Set password for LinuxGSM user "pwserver". Leave blank to generate a secure random password: ' password
    printf '\n'
  fi

  if [[ -z "$password" ]]; then
    PWSERVER_PASSWORD="$(generate_pwserver_password)"
    PWSERVER_PASSWORD_GENERATED="1"
  else
    PWSERVER_PASSWORD="$password"
    PWSERVER_PASSWORD_GENERATED="0"
  fi
}

set_pwserver_password() {
  msg_info "Setting pwserver Password"
  printf '%s\n' "$PWSERVER_PASSWORD" | pct exec "$CTID" -- bash -c 'IFS= read -r password; printf "%s:%s\n" "pwserver" "$password" | chpasswd'
  msg_ok "Set pwserver Password"
}

prompt_palworld_server_name() {
  local server_name="Palworld Server"

  if type -P whiptail >/dev/null 2>&1; then
    server_name=$(whiptail --title "Palworld Server Name" --inputbox "Set the public Palworld server name." 10 78 "Palworld Server" 3>&1 1>&2 2>&3) || exit 1
  else
    read -r -p 'Set the public Palworld server name [Palworld Server]: ' server_name
  fi

  if [[ -z "$server_name" ]]; then
    server_name="Palworld Server"
  fi

  PALWORLD_SERVER_NAME="$server_name"
}

header_info "$APP"
variables
color
catch_errors
prompt_pwserver_password
prompt_palworld_server_name

# Build a standard Ubuntu LXC with the Community Scripts installer, then run the
# Palworld/LinuxGSM provisioning steps from the Proxmox host with pct exec.
var_install="ubuntu-install"

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -x /home/pwserver/pwserver ]]; then
    msg_error "No ${APP} LinuxGSM Installation Found!"
    exit 1
  fi
  msg_info "Updating ${APP}"
  sudo -u pwserver -H bash -lc '/home/pwserver/pwserver update'
  msg_ok "Updated ${APP}"
  exit 0
}

ensure_container_running() {
  if ! pct status "$CTID" | grep -q "status: running"; then
    msg_info "Starting LXC Container"
    pct start "$CTID"
  fi

  for _ in {1..30}; do
    if pct status "$CTID" | grep -q "status: running"; then
      msg_ok "LXC Container is running"
      return 0
    fi
    sleep 1
  done

  msg_error "LXC Container ${CTID} is not running"
  exit 1
}

run_in_container() {
  pct exec "$CTID" -- bash -s "$@"
}

install_palworld() {
  local server_name_b64

  ensure_container_running
  server_name_b64="$(printf '%s' "$PALWORLD_SERVER_NAME" | base64 | tr -d '\n')"
  msg_info "Installing ${APP} Dedicated Server with LinuxGSM"
  run_in_container "$server_name_b64" <<'CT_SCRIPT'
set -Ee -o pipefail
export DEBIAN_FRONTEND=noninteractive
server_name="$(printf '%s' "$1" | base64 -d)"

apt-get update
apt-get install -y software-properties-common ca-certificates gnupg curl wget sudo debconf cron

dpkg --add-architecture i386
add-apt-repository -y multiverse || true
apt-get update

apt-get install -y \
  bc \
  binutils \
  bsdmainutils \
  bzip2 \
  ca-certificates \
  cpio \
  curl \
  distro-info \
  file \
  gzip \
  hostname \
  jq \
  lib32gcc-s1 \
  lib32stdc++6 \
  libsdl2-2.0-0:i386 \
  netcat-openbsd \
  pigz \
  python3 \
  sudo \
  tar \
  tmux \
  unzip \
  util-linux \
  uuid-runtime \
  wget \
  xz-utils

apt-get install -y netcat-openbsd || apt-get install -y netcat-traditional
if apt-cache show netcat >/dev/null 2>&1; then
  apt-get install -y netcat || true
fi
command -v nc >/dev/null

if apt-cache show steamcmd >/dev/null 2>&1; then
  printf 'steam steam/question select I AGREE\nsteam steam/license note \n' | debconf-set-selections || true
  apt-get install -y steamcmd || true
fi

if ! id pwserver >/dev/null 2>&1; then
  useradd -m -s /bin/bash pwserver
fi

install -d -o pwserver -g pwserver /home/pwserver
sudo -u pwserver -H bash -lc 'cd /home/pwserver && curl -Lo linuxgsm.sh https://linuxgsm.sh && chmod +x linuxgsm.sh && bash linuxgsm.sh pwserver'

sudo -u pwserver -H bash -lc 'cd /home/pwserver && ./pwserver auto-install' || \
  sudo -u pwserver -H bash -lc 'cd /home/pwserver && yes Y | ./pwserver install'

if [[ -f /home/pwserver/serverfiles/DefaultPalWorldSettings.ini && ! -s /home/pwserver/serverfiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini ]]; then
  install -d -o pwserver -g pwserver /home/pwserver/serverfiles/Pal/Saved/Config/LinuxServer
  install -o pwserver -g pwserver -m 0644 \
    /home/pwserver/serverfiles/DefaultPalWorldSettings.ini \
    /home/pwserver/serverfiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
fi

install -d -o pwserver -g pwserver /home/pwserver/lgsm/config-lgsm/pwserver
tmp_cfg="$(mktemp)"
if [[ -f /home/pwserver/lgsm/config-lgsm/pwserver/pwserver.cfg ]]; then
  grep -Ev '^(servername|startparameters)=' /home/pwserver/lgsm/config-lgsm/pwserver/pwserver.cfg >"${tmp_cfg}" || true
fi
printf 'servername=%q\n' "${server_name}" >>"${tmp_cfg}"
cat >>"${tmp_cfg}" <<'LGSMCFG'
startparameters="-publiclobby -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS -servername='${servername}' -port='${port}' -queryport='${steamport}'"
LGSMCFG
install -o pwserver -g pwserver -m 0644 "${tmp_cfg}" /home/pwserver/lgsm/config-lgsm/pwserver/pwserver.cfg
rm -f "${tmp_cfg}"

cat >/etc/systemd/system/pwserver.service <<'SERVICE'
[Unit]
Description=Palworld Dedicated Server managed by LinuxGSM
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
User=pwserver
Group=pwserver
WorkingDirectory=/home/pwserver
ExecStart=/home/pwserver/pwserver start
ExecStop=/home/pwserver/pwserver stop
ExecReload=/home/pwserver/pwserver restart
RemainAfterExit=yes
Restart=no
TimeoutStartSec=600
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable cron pwserver.service

crontab -u pwserver -l 2>/dev/null | grep -v '/home/pwserver/pwserver \(monitor\|update\|update-lgsm\)' >/tmp/pwserver.cron || true
cat >>/tmp/pwserver.cron <<'CRON'
*/5 * * * * /home/pwserver/pwserver monitor >/dev/null 2>&1
30 4 * * * /home/pwserver/pwserver update >/dev/null 2>&1
0 0 * * 0 /home/pwserver/pwserver update-lgsm >/dev/null 2>&1
CRON
crontab -u pwserver /tmp/pwserver.cron
rm -f /tmp/pwserver.cron

systemctl start cron
systemctl start pwserver.service
CT_SCRIPT
  set_pwserver_password
  msg_ok "Installed ${APP} Dedicated Server with LinuxGSM"
}

container_ip() {
  pct exec "$CTID" -- ip -4 addr show dev eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || true
}

print_completion() {
  IP="$(container_ip)"
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} Dedicated Server is ready.${CL}"
  echo -e "${INFO}${YW} Container IP:${CL} ${BGN}${IP:-Unknown}${CL}"
  echo -e "${INFO}${YW} Palworld server name:${CL} ${BGN}${PALWORLD_SERVER_NAME}${CL}"
  echo -e "${INFO}${YW} Root password:${CL} ${BGN}set during the installer wizard${CL}"
  if [[ "$PWSERVER_PASSWORD_GENERATED" == "1" ]]; then
    echo -e "${INFO}${YW} pwserver password:${CL} ${BGN}generated: ${PWSERVER_PASSWORD}${CL}"
  else
    echo -e "${INFO}${YW} pwserver password:${CL} ${BGN}user provided${CL}"
  fi
  echo -e "${INFO}${YW} LinuxGSM path:${CL} ${BGN}/home/pwserver${CL}"
  echo -e "${INFO}${YW} Palworld config:${CL} ${BGN}/home/pwserver/serverfiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini${CL}"
  echo -e "${INFO}${YW} LinuxGSM logs:${CL} ${BGN}/home/pwserver/log${CL}"
  echo -e "${INFO}${YW} Game logs:${CL} ${BGN}/home/pwserver/serverfiles/Pal/Saved/Logs${CL}"
  echo -e "${INFO}${YW} Open/forward these default UDP ports:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}8211/udp${CL} (game port)"
  echo -e "${TAB}${GATEWAY}${BGN}27015/udp${CL} (Steam query port)"
  echo -e "${INFO}${YW} Optional:${CL} forward ${BGN}25575/tcp${CL} only if you enable RCON. Use ${BGN}./pwserver details${CL} to confirm active ports."
  echo -e "${INFO}${YW} Useful LinuxGSM commands:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}su - pwserver${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}./pwserver details${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}./pwserver console${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}./pwserver restart${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}./pwserver update${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}./pwserver monitor${CL}"
}

start
build_container
description
install_palworld
print_completion
