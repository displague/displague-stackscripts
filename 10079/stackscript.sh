#!/bin/bash
# <UDF name="gh_username" Label="GitHub Username" example="GitHub User account to create with sudo access" />
source <ssinclude StackScriptID=1>

function btr_user_add_sudo {
  USERNAME="$1"
  USERPASS="$2"
  if [ ! -n "$USERNAME" ] || [ ! -n "$USERPASS" ]; then
    echo "No new username and/or password entered"
    return 1;
  fi

  [ -f /etc/debian_version ] && (
    adduser "$USERNAME" --disable-password --gecos ""
    echo "$USERNAME:$USERPASS" | chpasswd
    apt-get install -y sudo
    usermod -aG sudo "$USERNAME"
  )

  [ -f /etc/redhat-release ] && (
    adduser "$USERNAME" -p "$USERPASS"
    yum install -y sudo
    usermod -aG wheel "$USERNAME"
  )

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

    if [ "$USERNAME" == "root" ]; then
        mkdir /root/.ssh
        wget -q -O- "${GITHUBKEYS}" >> /root/.ssh/authorized_keys
        return 1;
    else
        mkdir -p /home/$USERNAME/.ssh
        wget -q -O- "${GITHUBKEYS}" >> /home/$USERNAME/.ssh/authorized_keys
        chown -R "$USERNAME":"$USERNAME" /home/$USERNAME/.ssh
    fi
}

echo "#################"
echo "########"
echo "########  G I T H U B :"
echo "  ======                $GH_USERNAME"
echo "  ======"
echo ""
echo "Creating user..."
btr_user_add_sudo "$GH_USERNAME" "$(randomString)"
passwd -d "$GH_USERNAME"

echo "Giving user passwordless sudo/su..."
sed -i 's/#\?\s*\(auth\s\+sufficient\s\+pam_wheel.so\s\+trust\)/\1/' /etc/pam.d/su
#sed -i "s/^root:.*/\0,$GH_USERNAME/" /etc/group
#sed -i "s/^wheel:.*/\0,$GH_USERNAME/" /etc/group

if [ -d /etc/sudoers.d ]; then
  SUDOERS="/etc/sudoers.d/$GH_USERNAME"
else
  SUDOERS=/etc/sudoers
fi

echo "$GH_USERNAME ALL=NOPASSWD: ALL" >> "$SUDOERS"
chmod 0440 "$SUDOERS"

echo "Adding GitHub SSH Keys..."
user_github_keys "$GH_USERNAME"

echo "Disabling Root SSH..."
ssh_disable_root

echo "Disabling Root Password..."
passwd -d root

echo "Disabling Root Shell..."
chsh -s $(which nologin) root

echo "Disabling NullOK Pam/Unix Auth for SecureTTYs..."
grep -l nullok_secure /etc/pam.d/* | while read pamf; do sed -i s/nullok_secure// $pamf; done

echo -e "\n\nPasswords have been disabled.\nUse SSH ssh://$GH_USERNAME@$(dnsdomainname -f)" >> /etc/issue

echo "Done."
echo ""
echo "  ======"
echo "########"
echo "########"
