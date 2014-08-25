#!/bin/bash
# <UDF name="gh_username" Label="GitHub Username" example="GitHub User account to create with sudo access" />
source <ssinclude StackScriptID=1>

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
user_add_sudo "$GH_USERNAME" "$(randomString)"
passwd -d "$GH_USERNAME"
sed -Ei 's/#?\s*(auth\s+sufficient\s+pam_wheel.so\s+trust)/\1/' /etc/pam.d/su
sed -Ei "s/^root:.*/\0$GH_USERNAME/" /etc/group
echo "$GH_USERNAME ALL=NOPASSWD: ALL" > "/etc/sudoers.d/$GH_USERNAME"
echo "Adding GitHub SSH Keys..."
user_github_keys "$GH_USERNAME"
echo "Disabling Root SSH..."
ssh_disable_root
echo "Disabling Root Password..."
passwd -d root
echo "Disabling Root Shell..."
chsh -s /usr/sbin/nologin root
echo "Disabling NullOK Pam/Unix Auth for SecureTTYs..."
grep -l nullok_secure /etc/pam.d/* | while read pamf; do sed -i s/nullok_secure// $pamf; done
echo -e "\n\nPasswords have been disabled.\nUse SSH ssh://$GH_USERNAME@$(hostname -A)" >> /etc/issue
echo "Done."
echo ""
echo "  ======"
echo "########"
echo "########"
