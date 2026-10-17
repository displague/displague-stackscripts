# Rootless and GitHub User has sudo

Sick of passwords?  Have a GitHub account configured with your favorite ssh keys?

You've come to the right place.  This StackScript removes the barrier to entry.  The root password has been disabled, so you can't ssh in as root.  But wait, root is not out of reach!  

With one simple text entry of your GitHub username, all of your GitHub configured ssh keys will be authorized for login with your existing GitHub username.  Root password? Who needs it.  While you will be prompted for one, this miracle script will promptly remove the root password on first boot.

Your GitHub username is all you need to sudo or su.  No more secrets!

## Try it on a Linode
https://cloud.linode.com/stackscripts/10079

### Deploy with `linode-cli`

```sh
$ pip install linode-cli
$ read -s -p "Temporary root password: " ROOT_PASS; echo
$ linode-cli linodes create \
    --type g6-nanode-1 \
    --region us-central \
    --image linode/debian13 \
    --label rootless-github \
    --root_pass "${ROOT_PASS}" \
    --stackscript_id 10079 \
    --stackscript_data '{"gh_username":"YOUR_GITHUB_USERNAME"}'
```

### Cloud-Init Equivalent

On Linode images that natively support `cloud-init` (all modern images except `linode/slackware15.0`), the equivalent setup can be accomplished directly with the following `#cloud-config` passed via `--metadata.user_data`:

```yaml
# /tmp/user-data
#cloud-config
ssh_import_id:
  - gh:YOUR_GITHUB_USERNAME

# Optional: ensure password authentication is disabled and root login is locked
disable_root: true
ssh_pwauth: false
```

```sh
$ linode-cli linodes create \
    --type g6-nanode-1 \
    --region us-central \
    --image linode/debian13 \
    --label rootless-cloudinit \
    --root_pass "${ROOT_PASS}" \
    --metadata.user_data "$(base64 -w 0 /tmp/user-data)"
```

## Yada, Yada
Copyright Marques Johansson, 2014.
Released under the MIT License

Send comments to @displague
