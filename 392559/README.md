# CloudInit

This StackScript takes a base64 encoded `userdata` variable which will be provided to `cloud-init` on boot.

* https://cloud.linode.com/stackscripts/392559

> **Note:** Most current Linode OS images now natively support the `cloud-init` capability (`--metadata.user_data`). This StackScript remains useful for images that do not natively advertise `cloud-init` support (such as `linode/slackware15.0`) or workflows standardized on StackScript UDFs.

## Deploy with `linode-cli`

For example, to import your GitHub SSH keys and disable password/root password authentication via `#cloud-config`:

```yaml
# /tmp/user-data
#cloud-config
ssh_import_id:
  - gh:YOUR_GITHUB_USERNAME

# Optional: ensure password authentication is disabled and root login is locked
disable_root: true
ssh_pwauth: false
```

The following snippet boots a Linode instance using any she-bang script or Cloud-Init UserData from the local `/tmp/user-data` file (which can also be `gzip`'ed):

```sh
$ pip install linode-cli
$ read -s -p "password: " ROOT_PASS; echo
$ linode-cli linodes create \
    --type g6-nanode-1 \
    --region us-central \
    --image linode/slackware15.0 \
    --root_pass="${ROOT_PASS}" \
    --label=cloudinittest \
    --stackscript_id=392559 \
    --stackscript_data='{"userdata":"'$(base64 -w 0 /tmp/user-data)'"}'
```

*(On images with native `cloud-init` capability, you can also pass `--metadata.user_data="$(base64 -w 0 /tmp/user-data)"` directly to `linode-cli linodes create`.)*

## References
* [Cloud-Init Documentation — Examples](https://cloudinit.readthedocs.io/en/latest/topics/examples.html)
* [Use cloud-init to Automatically Configure and Secure Your Servers](https://www.akamai.com/cloud/guides/applications/configuration-management/cloud-init)
* [Overview of the Metadata Service — Add User Data](https://techdocs.akamai.com/cloud-computing/docs/overview-of-the-metadata-service#add-user-data)
* [Add User Data When Deploying a Compute Instance](https://techdocs.akamai.com/cloud-computing/docs/add-user-data-when-deploying-a-compute-instance)
* [Get Images API (`capabilities`)](https://techdocs.akamai.com/linode-api/reference/get-images)
