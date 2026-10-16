#!/bin/bash
# <UDF name="gh_username" Label="GitHub Username" example="GitHub User account to create with sudo access (use spaces or commas for multiple accounts)" />
source <ssinclude StackScriptID=1>

if ! type randomString >/dev/null 2>&1; then
  function randomString {
    local length="${1:-20}"
    </dev/urandom tr -dc A-Za-z0-9 | head -c "$length"
    echo
  }
fi

function btr_user_add_sudo {
  USERNAME="$1"
  USERPASS="$2"
  if [ ! -n "$USERNAME" ] || [ ! -n "$USERPASS" ]; then
    echo "No new username and/or password entered"
    return 1;
  fi

  local USER_SHELL="/bin/bash"
  [ ! -x "$USER_SHELL" ] && USER_SHELL="$(command -v bash || echo /bin/sh)"

  if [ -f /etc/debian_version ]; then
    adduser "$USERNAME" --disabled-password --gecos "" || useradd -m -s "$USER_SHELL" "$USERNAME"
    echo "$USERNAME:$USERPASS" | chpasswd
    if ! command -v sudo >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y sudo
    fi
    usermod -aG sudo "$USERNAME" 2>/dev/null || usermod -aG wheel "$USERNAME" 2>/dev/null || true
  elif [ -f /etc/redhat-release ]; then
    useradd -m -s "$USER_SHELL" "$USERNAME"
    echo "$USERNAME:$USERPASS" | chpasswd
    if ! command -v sudo >/dev/null 2>&1; then
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y sudo
      else
        yum install -y sudo
      fi
    fi
    usermod -aG wheel "$USERNAME"
  elif [ -f /etc/alpine-release ]; then
    adduser -D -s "$USER_SHELL" "$USERNAME" || useradd -m -s "$USER_SHELL" "$USERNAME"
    echo "$USERNAME:$USERPASS" | chpasswd
    if ! command -v sudo >/dev/null 2>&1; then
      apk update && apk add sudo
    fi
    addgroup "$USERNAME" wheel 2>/dev/null || usermod -aG wheel "$USERNAME" 2>/dev/null || true
  elif [ -f /etc/arch-release ]; then
    useradd -m -s "$USER_SHELL" "$USERNAME"
    echo "$USERNAME:$USERPASS" | chpasswd
    if ! command -v sudo >/dev/null 2>&1; then
      pacman -Sy --noconfirm sudo
    fi
    usermod -aG wheel "$USERNAME" 2>/dev/null || true
  elif [ -f /etc/SuSE-release ] || grep -qi "suse" /etc/os-release 2>/dev/null; then
    useradd -m -s "$USER_SHELL" "$USERNAME"
    echo "$USERNAME:$USERPASS" | chpasswd
    if ! command -v sudo >/dev/null 2>&1; then
      zypper --non-interactive install sudo
    fi
    usermod -aG wheel "$USERNAME" 2>/dev/null || true
  else
    # Slackware, Gentoo, or other generic Linux
    useradd -m -s "$USER_SHELL" "$USERNAME" || adduser -D -s "$USER_SHELL" "$USERNAME"
    echo "$USERNAME:$USERPASS" | chpasswd
    usermod -aG wheel "$USERNAME" 2>/dev/null || gpasswd -a "$USERNAME" wheel 2>/dev/null || true
  fi
}

# Fetch GitHub SSH Keys
function user_github_keys {
    # Adds the users public key to authorized_keys for the specified user. Make sure you wrap your input variables in double quotes, or the key may not load properly.
    #
    #
    # $1 - Required - username
    USERNAME="${1}"
    GITHUBKEYS="https://github.com/${1}.keys"

    if [ ! -n "$USERNAME" ]; then
        echo "Must provide a username"
        return 1;
    fi

    HDIR="$(getent passwd "$USERNAME" 2>/dev/null | cut -f6 -d:)"
    [ -z "$HDIR" ] && HDIR="$(grep "^${USERNAME}:" /etc/passwd | cut -f6 -d:)"
    mkdir -p "$HDIR/.ssh"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${GITHUBKEYS}" >> "$HDIR/.ssh/authorized_keys"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O- "${GITHUBKEYS}" >> "$HDIR/.ssh/authorized_keys"
    else
        if [ -f /etc/debian_version ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y curl
        elif [ -f /etc/redhat-release ]; then
            (command -v dnf >/dev/null 2>&1 && dnf install -y curl) || yum install -y curl
        elif [ -f /etc/alpine-release ]; then
            apk add --no-cache curl
        elif [ -f /etc/arch-release ]; then
            pacman -Sy --noconfirm curl
        elif grep -qi "suse" /etc/os-release 2>/dev/null; then
            zypper --non-interactive install curl
        fi
        curl -fsSL "${GITHUBKEYS}" >> "$HDIR/.ssh/authorized_keys"
    fi
    chown -R "$USERNAME":"$USERNAME" "$HDIR/.ssh" 2>/dev/null || chown -R "$USERNAME" "$HDIR/.ssh"
    chmod 700 "$HDIR/.ssh"
    chmod 600 "$HDIR/.ssh/authorized_keys"
    command -v restorecon >/dev/null 2>&1 && restorecon -R -v "$HDIR/.ssh"
}

echo -e "\n\nPasswords have been disabled. Use SSH:\n" >> /etc/issue

export ALL_GH_USERNAMES="${GH_USERNAME//,/ }"
FQDN="$(hostname -f 2>/dev/null || dnsdomainname -f 2>/dev/null || hostname 2>/dev/null || uname -n)"

for GH_USERNAME in ${ALL_GH_USERNAMES}; do
echo "#################"
echo "########"
echo "########  G I T H U B :"
echo "  ======                $GH_USERNAME"
echo "  ======"
echo ""
echo "Creating user..."
btr_user_add_sudo "$GH_USERNAME" "$(randomString)"
passwd -d "$GH_USERNAME" 2>/dev/null || passwd -u "$GH_USERNAME" 2>/dev/null || true
usermod -U "$GH_USERNAME" 2>/dev/null || true

echo "Giving user passwordless sudo/su..."
[ -f /etc/pam.d/su ] && sed -i 's/#\?\s*\(auth\s\+sufficient\s\+pam_wheel.so\s\+trust\)/\1/' /etc/pam.d/su
#sed -i "s/^root:.*/\0,$GH_USERNAME/" /etc/group
#sed -i "s/^wheel:.*/\0,$GH_USERNAME/" /etc/group

if [ -d /etc/sudoers.d ]; then
  if [ -f /etc/sudoers ] && ! grep -qE '^[#@]includedir[[:space:]]+/etc/sudoers\.d' /etc/sudoers; then
    echo "#includedir /etc/sudoers.d" >> /etc/sudoers
  fi
  SUDOERS="/etc/sudoers.d/$GH_USERNAME"
else
  SUDOERS=/etc/sudoers
fi

echo "$GH_USERNAME ALL=NOPASSWD: ALL" >> "$SUDOERS"
chmod 0440 "$SUDOERS"

echo "Adding GitHub SSH Keys..."
user_github_keys "$GH_USERNAME"

echo -e "    ssh://$GH_USERNAME@$FQDN" >> /etc/issue

done

echo "Disabling Root SSH..."
type ssh_disable_root >/dev/null 2>&1 && ssh_disable_root
if [ -f /etc/ssh/sshd_config ]; then
  sed -i -e "s/^#\?PermitRootLogin.*/PermitRootLogin no/" \
         -e "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" \
         -e "s/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/" /etc/ssh/sshd_config
  grep -q "^PermitRootLogin no" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi
if [ -d /etc/ssh/sshd_config.d ]; then
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] || continue
    sed -i -e "s/^PermitRootLogin.*/PermitRootLogin no/" \
           -e "s/^PasswordAuthentication.*/PasswordAuthentication no/" \
           -e "s/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/" "$f"
  done
  cat <<SSHEOF > /etc/ssh/sshd_config.d/00-disable-root-and-passwords.conf
PermitRootLogin no
PasswordAuthentication no
SSHEOF
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
fi
if command -v rc-service >/dev/null 2>&1; then
  rc-service sshd reload 2>/dev/null || rc-service sshd restart 2>/dev/null || true
fi
if [ -x /etc/rc.d/rc.sshd ]; then
  /etc/rc.d/rc.sshd restart 2>/dev/null || true
elif [ -x /etc/init.d/sshd ]; then
  /etc/init.d/sshd reload 2>/dev/null || /etc/init.d/sshd restart 2>/dev/null || true
elif [ -x /etc/init.d/ssh ]; then
  /etc/init.d/ssh reload 2>/dev/null || /etc/init.d/ssh restart 2>/dev/null || true
fi

echo "Disabling Root Password..."
passwd -d root 2>/dev/null || passwd -l root 2>/dev/null || true

echo "Disabling Root Shell..."
NOLOGIN_BIN="$(command -v nologin || which nologin 2>/dev/null || echo /sbin/nologin)"
[ ! -e "$NOLOGIN_BIN" ] && [ -e /usr/sbin/nologin ] && NOLOGIN_BIN="/usr/sbin/nologin"
if command -v usermod >/dev/null 2>&1; then
  usermod -s "$NOLOGIN_BIN" root 2>/dev/null || sed -i "s|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*|\1$NOLOGIN_BIN|" /etc/passwd
elif command -v chsh >/dev/null 2>&1; then
  chsh -s "$NOLOGIN_BIN" root 2>/dev/null || sed -i "s|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*|\1$NOLOGIN_BIN|" /etc/passwd
else
  sed -i "s|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\).*|\1$NOLOGIN_BIN|" /etc/passwd
fi

echo "Disabling NullOK Pam/Unix Auth for SecureTTYs..."
grep -l nullok_secure /etc/pam.d/* 2>/dev/null | while read pamf; do sed -i s/nullok_secure// "$pamf"; done

echo "Done."
echo ""
echo "  ======"
echo "########"
echo "########"
