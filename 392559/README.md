This StackScript takes a base64 encoded `userdata` variable which will be provided to `cloud-init` on boot.

The following snippet would boot a Linode instance using any she-bang script or Cloud-Init UserData from the local `/tmp/user-data` file.  This file can also be gzip'ed.

```sh
$ pip install linode-cli
$ read -s -p "password: " ROOT_PASS; echo
$ linode-cli linodes create \
    --root_pass=${ROOT_PASS} \
    --label=cloudinittest \
    --stackscript_id=392559 \
    --stackscript_data='{"userdata":"'$(base64 -i /tmp/user-data)'"}'
```

See <https://cloudinit.readthedocs.io/en/latest/topics/examples.html> for example of UserData files.
