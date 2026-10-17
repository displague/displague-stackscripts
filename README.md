# Linode StackScripts by Marques Johansson

Collection of Linode StackScripts, configuration metadata, and automated integration tests.

---

## StackScripts

### [10079 — Rootless and GitHub User has sudo](./10079/)
* **Linode Cloud Manager**: <https://cloud.linode.com/stackscripts/10079>
* **Description**: Creates one or more user accounts from GitHub usernames (`gh_username`, comma- or space-separated), imports their public SSH keys from `https://github.com/<username>.keys`, configures passwordless `sudo`/`su`, disables `root` SSH and password authentication, and sets `root`'s login shell to `nologin`.
* **Quick Deploy (`linode-cli`)**:
  ```sh
  linode-cli linodes create \
    --type g6-nanode-1 \
    --region us-central \
    --image linode/debian13 \
    --label rootless-github \
    --root_pass "$(openssl rand -base64 24)" \
    --stackscript_id 10079 \
    --stackscript_data '{"gh_username":"YOUR_GITHUB_USERNAME"}'
  ```

### [392559 — CloudInit](./392559/)
* **Linode Cloud Manager**: <https://cloud.linode.com/stackscripts/392559>
* **Description**: Accepts a base64-encoded (optionally `gzip`'ed) `userdata` UDF payload, seeds `/var/lib/cloud/seed/nocloud-net/user-data`, runs `cloud-init`, and provides built-in fallback support for `#cloud-config` `ssh_import_id: [gh:...]`, `disable_root: true`, and `ssh_pwauth: false` on distributions without native `cloud-init` support (such as `linode/slackware15.0`).
* **Quick Deploy (`linode-cli`)**:
  ```sh
  linode-cli linodes create \
    --type g6-nanode-1 \
    --region us-central \
    --image linode/slackware15.0 \
    --label cloudinit-test \
    --root_pass "$(openssl rand -base64 24)" \
    --stackscript_id 392559 \
    --stackscript_data '{"userdata":"'$(base64 -w 0 /tmp/user-data)'"}'
  ```

---

## Cloud-Init Native Equivalent

On Linode images that advertise the native `cloud-init` capability (`linode-cli images list --json`), you can pass `#cloud-config` user-data directly via `--metadata.user_data` at creation time:

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
linode-cli linodes create \
  --type g6-nanode-1 \
  --region us-central \
  --image linode/debian13 \
  --label rootless-cloudinit \
  --root_pass "$(openssl rand -base64 24)" \
  --metadata.user_data "$(base64 -w 0 /tmp/user-data)"
```

---

## Repository Usage & Testing

Each StackScript resides in its own `<id>/` directory containing:
* `<id>/stackscript.sh` — The StackScript payload.
* `<id>/images.txt` — Supported Linode image IDs.
* `<id>/README.md` — StackScript documentation and examples.
* `<id>/tests/test_stackscript.sh` — Automated parallel Nanode integration test suite.

### Commands

```sh
# View local StackScript summaries
make summary

# Sync local stackscript.sh and images.txt to Linode via linode-cli
make update

# Run all <id>/tests/test_stackscript.sh suites in parallel
make test

# Test a single StackScript or specific OS images
make test-10079
IMAGES="linode/debian13 linode/rocky10" make test-10079
```

## License

Released under the [MIT License](./LICENSE).
