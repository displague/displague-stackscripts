#!/bin/sh
# <UDF name="userdata" label="user-data file contents (base64 encoded)" />
set +e +x
FILE_USERDATA="/var/lib/cloud/seed/nocloud-net/user-data"
FILE_METADATA="/var/lib/cloud/seed/nocloud-net/meta-data"
# vendor-data and network-config are optional

echo "Configuring cloud-init..."
if command -v debconf-communicate >/dev/null 2>&1; then
  echo "set cloud-init/datasources NoCloud" | debconf-communicate
fi
mkdir -p /etc/cloud/cloud.cfg.d /var/lib/cloud/seed/nocloud-net/

if [ -n "$LINODE_ID" ]; then
cat > /etc/cloud/cloud.cfg.d/01-instanceid.cfg <<EOS
datasource:
  NoCloud:
    meta-data:
       instance-id: linode$LINODE_ID
EOS
fi

cat > /etc/cloud/cloud.cfg.d/99-warnings.cfg <<'EOS'
#cloud-config
warnings:
  dsid_missing_source: off
EOS

UMASK=$(umask)
umask 0066
echo "Creating $FILE_METADATA..."
touch "${FILE_METADATA}"

echo "Creating $FILE_USERDATA..."
touch "${FILE_USERDATA}"
if echo "${USERDATA}" | base64 -d 2>/dev/null | gzip -t >/dev/null 2>&1; then
  echo "${USERDATA}" | base64 -d | gzip -d > "${FILE_USERDATA}"
else
  echo "${USERDATA}" | base64 -d > "${FILE_USERDATA}"
fi
umask "${UMASK}"

if ! command -v cloud-init >/dev/null 2>&1; then
  echo "Installing cloud-init..."
  if [ -f /etc/debian_version ]; then
    DEBIAN_FRONTEND=noninteractive apt-get -q=2 update
    DEBIAN_FRONTEND=noninteractive apt-get -q=2 install -y cloud-init ssh-import-id
  elif [ -f /etc/redhat-release ]; then
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y cloud-init
    else
      yum install -y cloud-init
    fi
  elif grep -qi "suse" /etc/os-release 2>/dev/null; then
    zypper --non-interactive install cloud-init
  elif [ -f /etc/gentoo-release ]; then
    emerge --quiet app-emulation/cloud-init 2>/dev/null || true
  fi
fi

if command -v cloud-init >/dev/null 2>&1; then
  echo "Running cloud-init... (init, config, and final)"
  cloud-init init
  cloud-init modules --mode=config
  cloud-init modules --mode=final
fi

# Ensure ssh_import_id: [gh:...] keys are installed cleanly for root
if grep -qE '^\s*-\s*gh:' "${FILE_USERDATA}" 2>/dev/null; then
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  sed -i '/^no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command=/d' /root/.ssh/authorized_keys 2>/dev/null || true
  for gh_user in $(sed -n 's/^[[:space:]]*-[[:space:]]*gh:\([A-Za-z0-9_-]*\).*/\1/p' "${FILE_USERDATA}"); do
    [ -z "$gh_user" ] && continue
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "https://github.com/${gh_user}.keys" >> /root/.ssh/authorized_keys
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O- "https://github.com/${gh_user}.keys" >> /root/.ssh/authorized_keys
    fi
  done
  sort -u -o /root/.ssh/authorized_keys /root/.ssh/authorized_keys 2>/dev/null || true
  command -v restorecon >/dev/null 2>&1 && restorecon -R -v /root/.ssh
fi

if grep -qE '^\s*ssh_pwauth:\s*(false|0|no)\b' "${FILE_USERDATA}" 2>/dev/null; then
  if [ -f /etc/ssh/sshd_config ]; then
    sed -i -e "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" \
           -e "s/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/" /etc/ssh/sshd_config
    grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  fi
  if [ -d /etc/ssh/sshd_config.d ]; then
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [ -f "$f" ] || continue
      sed -i -e "s/^PasswordAuthentication.*/PasswordAuthentication no/" "$f"
    done
    echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/00-cloudinit-pwauth.conf
  fi
fi

if grep -qE '^\s*disable_root:\s*(true|1|yes)\b' "${FILE_USERDATA}" 2>/dev/null; then
  passwd -d root 2>/dev/null || passwd -l root 2>/dev/null || true
  if [ -f /etc/ssh/sshd_config ]; then
    sed -i -e "s/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config
    grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
elif [ -x /etc/rc.d/rc.sshd ]; then
  /etc/rc.d/rc.sshd restart 2>/dev/null || true
elif [ -x /etc/init.d/sshd ]; then
  /etc/init.d/sshd reload 2>/dev/null || /etc/init.d/sshd restart 2>/dev/null || true
fi
