# Agent & Developer Guide (`displague-stackscripts`)

This repository contains Linode StackScripts, configuration metadata, and automated integration tests.

- **StackScript 10079 (`10079/`)**: [Rootless and GitHub User has sudo](https://cloud.linode.com/stackscripts/10079)
- **StackScript 392559 (`392559/`)**: [CloudInit](https://cloud.linode.com/stackscripts/392559)

---

## Repository Structure

- `<stackscript_id>/stackscript.sh`: The StackScript payload deployed to Linode.
- `<stackscript_id>/images.txt`: Newline-delimited list of Linode image IDs (e.g., `linode/debian13`) supported by the StackScript.
- `<stackscript_id>/README.md`: Documentation and `linode-cli` usage examples for the StackScript.
- `<stackscript_id>/tests/test_stackscript.sh`: Parallel integration test runner that provisions ephemeral `g6-nanode-1` instances, verifies the StackScript effects over SSH, and tears down all test instances on exit.
- `update-stackscripts`: Python 3 CLI utility wrapping `linode-cli --json` to view or update StackScripts (`./update-stackscripts summary`, `./update-stackscripts update [id]`).
- `Makefile`: Root task runner (`make test`, `make update`, `make summary`).

---

## Linode StackScript Deployment & OS Nuances

### 1. StackScript API & Image Validation
- When updating a StackScript via `linode-cli stackscripts update <id>`, the Linode API validates every image ID in `--images` against currently active public images (`linode-cli images list --json`).
- Deprecated/retired image IDs (even if previously attached to an older revision of a StackScript) are rejected with `400 [{"field": "images", "reason": "Invalid value"}]`. Always filter against currently available images.
- StackScripts must have at least one image attached.
- Public StackScript URLs now use `https://cloud.linode.com/stackscripts/<id>` (require Cloud Manager login); the legacy `https://www.linode.com/stackscripts/view/<id>` route is retired.

### 2. Legacy `StackScriptID=1` (`<ssinclude StackScriptID=1>`)
- StackScript `10079` includes `source <ssinclude StackScriptID=1>` ([StackScript Bash Library](https://cloud.linode.com/stackscripts/1)), which was last updated in 2020.
- Even though `StackScriptID=1`'s own metadata only lists older OS images, Linode's provisioning agent still injects `/root/ssinclude-1` on all distributions that support StackScripts.
- However, `StackScriptID=1`'s `detect_distro` only checks `/etc/debian_version` and `/etc/redhat-release`, and its `ssh_disable_root` function only edits `/etc/ssh/sshd_config` and only restarts `ssh`/`sshd` for `debian` or `redhat` families.
- **Best practice**: Do not rely solely on `StackScriptID=1` functions for modern OS families. Provide fallback definitions (e.g., `randomString`) and handle `sshd` drop-in configs and service reloads directly.

### 3. Modern OS Compatibility Pitfalls
- **Cloud-Init & `/etc/ssh/sshd_config.d/*.conf`**:
  - Modern Debian, Ubuntu, Fedora, and RHEL-family images include `/etc/ssh/sshd_config.d/*.conf` drop-ins (such as `50-cloud-init.conf`) BEFORE the main `/etc/ssh/sshd_config` directives.
  - Because `sshd` uses a first-match-wins model, modifying only `/etc/ssh/sshd_config` is insufficient if a drop-in file sets `PasswordAuthentication yes` or `PermitRootLogin yes`.
  - Always sanitize `/etc/ssh/sshd_config.d/*.conf` and/or write an early drop-in like `/etc/ssh/sshd_config.d/00-disable-root-and-passwords.conf`, then reload `sshd`.
- **SELinux Contexts (`restorecon`)**:
  - On RHEL-family distributions (AlmaLinux, Rocky Linux, CentOS Stream, Fedora), creating `~/.ssh/authorized_keys` as `root` inside a StackScript can leave `~/.ssh` with an unlabeled or `user_home_dir_t` SELinux context instead of `ssh_home_t`, causing `sshd` to reject public-key authentication.
  - Always run `command -v restorecon >/dev/null 2>&1 && restorecon -R -v "$HDIR/.ssh"` after writing SSH keys.
- **Locked vs. Passwordless Accounts in OpenSSH (`passwd -d` / `usermod -U`)**:
  - On some distributions (`useradd` without `-p`), new accounts have `!` or `!!` in `/etc/shadow`, which OpenSSH treats as a locked account and may refuse public-key login unless `passwd -d <user>` / `usermod -U <user>` is run.
- **Minimal Base Images (`adduser`, `chsh`, `curl`, `wget`, `dnsdomainname`)**:
  - Newer Debian (12/13) and minimal RHEL/Fedora/Gentoo/openSUSE images may omit `adduser`, `chsh`, `wget`, or `dnsdomainname`.
  - Use `useradd -m -s /bin/bash` as a fallback for `adduser`, `usermod -s` as a fallback for `chsh`, `curl -fsSL` with fallback to `wget -q -O-`, and `hostname -f` / `hostname` as fallbacks for `dnsdomainname -f`.
  - Only run package index updates (`apt-get update`, `dnf`, `zypper`) when a required binary (`sudo`, `curl`, `cloud-init`) is actually missing—unconditional `apt-get update` during first boot slows provisioning by 30–90 seconds and can contend with background timers.
- **`/etc/sudoers.d` Include Directive**:
  - On Slackware and Gentoo, `/etc/sudoers.d` may exist on disk while `#includedir /etc/sudoers.d` is commented out in `/etc/sudoers`. Ensure `^[#@]includedir[[:space:]]+/etc/sudoers\.d` is present in `/etc/sudoers` before writing drop-in files to `/etc/sudoers.d/`.
- **Alpine & Arch Linux StackScript Execution**:
  - Linode's current `linode/arch` and `linode/alpine*` images boot using `DataSourceAkamaiLocal` cloud-init without a first-boot service or `rc.local` hook to execute `/root/StackScript` (and Alpine does not ship `/bin/bash` by default). Those images should be excluded from StackScript `images.txt` lists unless upstream image support changes.

### 4. Native `cloud-init` Capability vs. StackScript 392559
- You can inspect image capabilities via:
  ```sh
  linode-cli images list --json | jq '[.[] | select(.is_public == true) | {id, capabilities}]'
  ```
- Almost all modern Linode images advertise `"capabilities": ["cloud-init"]` and accept `--metadata.user_data` (base64-encoded `#cloud-config` or user-data scripts) directly at creation time.
- Currently, `linode/slackware15.0` is the only active public OS image with `"capabilities": []` (no native `cloud-init`).
- StackScript `392559` (`CloudInit`) bridges this gap by writing `/var/lib/cloud/seed/nocloud-net/user-data`, running `cloud-init` if available/installable, and providing a built-in fallback for common `#cloud-config` directives (`ssh_import_id: [gh:...]`, `disable_root: true`, `ssh_pwauth: false`) on distros like Slackware that do not package `cloud-init` or `ssh-import-id`.

---

## Testing & Verification Workflow

- **Running Tests**:
  - Run `make test` from the repository root to execute all `*/tests/test*.sh` scripts.
  - By default, `392559/tests/test_stackscript.sh` queries `linode-cli images list --json` and skips images that already advertise native `cloud-init` capability (`SKIP_CLOUD_INIT_CAPABLE=true`), testing only images that lack native `cloud-init` (such as `linode/slackware15.0`). Set `SKIP_CLOUD_INIT_CAPABLE=false` to force testing across all configured images.
  - Filter to specific images with `IMAGES="linode/debian13 linode/rocky10" make test`.
- **Parallel Provisioning Tips**:
  - Distribute parallel test instances across regions (`us-central`, `us-east`, `us-west`, `us-ord`, `us-southeast`) and use uniquely suffixed labels (`ss<id>-<distro>`) so concurrent runs never collide on label uniqueness or single-region queueing.
  - Always register an `EXIT` trap (`trap cleanup EXIT`) that deletes every created Linode ID so no orphaned instances remain even if a test fails or is interrupted.
- **Debugging Boot / StackScript Failures**:
  - If an instance fails SSH verification during testing, you can inspect its serial console / boot logs via LISH (`ssh <linode-user>@lish-<region>.linode.com <linode-label>`) or inspect `/var/log/stackscript.log` and `journalctl -u sshd` before tearing down the instance.
