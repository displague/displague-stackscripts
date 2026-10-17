#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STACKSCRIPT_ID="${STACKSCRIPT_ID:-$(basename "$SS_DIR")}"
GH_USERNAME="${GH_USERNAME:-$(gh api user -q .login 2>/dev/null || git config github.user 2>/dev/null || echo "${USER:-}")}"
if [ -z "$GH_USERNAME" ]; then
  echo "Error: GH_USERNAME must be set (or logged in via 'gh auth login')" >&2
  exit 1
fi
LINODE_TYPE="${LINODE_TYPE:-g6-nanode-1}"
REGIONS=(${LINODE_REGIONS:-us-central us-east us-west us-ord us-southeast})
SKIP_CLOUD_INIT_CAPABLE="${SKIP_CLOUD_INIT_CAPABLE:-true}"

if [ -n "${IMAGES:-}" ]; then
  read -r -a RAW_IMAGES <<< "$IMAGES"
elif [ -f "$SS_DIR/images.txt" ]; then
  mapfile -t RAW_IMAGES < <(grep -vE '^\s*(#|$)' "$SS_DIR/images.txt")
else
  mapfile -t RAW_IMAGES < <(linode-cli stackscripts view "$STACKSCRIPT_ID" --json | jq -r '.[0].images[]')
fi

IMAGE_LIST=()
if [ "$SKIP_CLOUD_INIT_CAPABLE" = "true" ]; then
  echo "Checking Linode image capabilities (skipping images with native 'cloud-init' capability)..."
  CAPABLE_IMAGES="$(linode-cli images list --json | jq -r '.[] | select(.capabilities != null and (.capabilities | index("cloud-init"))) | .id')"
  for img in "${RAW_IMAGES[@]}"; do
    if grep -qx "$img" <<<"$CAPABLE_IMAGES"; then
      echo "SKIP [$img]: Image natively supports 'cloud-init' capability"
    else
      IMAGE_LIST+=("$img")
    fi
  done
else
  IMAGE_LIST=("${RAW_IMAGES[@]}")
fi

if [ "${#IMAGE_LIST[@]}" -eq 0 ]; then
  echo "No non-cloud-init images to test."
  exit 0
fi

USERDATA_B64="$(cat <<UD | base64 -w 0
#cloud-config
ssh_import_id:
  - gh:${GH_USERNAME}

# Optional: ensure password authentication is disabled and root login is locked
disable_root: true
ssh_pwauth: false
UD
)"

WORKDIR="$(mktemp -d -t "ss${STACKSCRIPT_ID}-verify-XXXXXX")"

cleanup() {
  echo "Cleaning up any remaining test Linodes..."
  for id_file in "$WORKDIR"/*.id; do
    [ -f "$id_file" ] || continue
    lid="$(cat "$id_file")"
    if [ -n "$lid" ]; then
      echo "Deleting Linode $lid..."
      linode-cli linodes delete "$lid" >/dev/null 2>&1 || true
      rm -f "$id_file"
    fi
  done
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

test_image() {
  local img="$1"
  local region="$2"
  local slug="${img#linode/}"
  local label="ss${STACKSCRIPT_ID}-${slug//./-}"
  local log="$WORKDIR/${slug}.log"
  local id_file="$WORKDIR/${slug}.id"
  local root_pass="TempRootPass!987654"

  echo "[$(date +%H:%M:%S)] Creating $label ($img) in $region..." | tee "$log"
  local out=""
  for try in 1 2 3; do
    if out=$(linode-cli linodes create \
      --type "$LINODE_TYPE" \
      --region "$region" \
      --image "$img" \
      --label "$label" \
      --root_pass "$root_pass" \
      --stackscript_id "$STACKSCRIPT_ID" \
      --stackscript_data "{\"userdata\": \"$USERDATA_B64\"}" \
      --json 2>>"$log"); then
      break
    fi
    sleep $((try * 3))
  done

  if [ -z "$out" ]; then
    echo "FAIL [$img]: Failed to create Linode" | tee -a "$log"
    return 1
  fi

  local lid ip
  lid=$(echo "$out" | jq -r '.[0].id')
  ip=$(echo "$out" | jq -r '.[0].ipv4[0]')
  echo "$lid" > "$id_file"
  echo "[$(date +%H:%M:%S)] Created $label: ID=$lid IP=$ip" | tee -a "$log"

  local attempt=0
  local max_attempts=50
  local ssh_ok=0
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    sleep 8
    if ssh -o BatchMode=yes \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 \
           "root@${ip}" "grep -q '.' /root/.ssh/authorized_keys && grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config" >>"$log" 2>&1; then
      ssh_ok=1
      break
    fi
  done

  if [ "$ssh_ok" -ne 1 ]; then
    echo "FAIL [$img]: Could not verify cloud-init SSH key + ssh_pwauth setup on root@$ip after $((max_attempts * 8))s" | tee -a "$log"
    linode-cli linodes delete "$lid" >>"$log" 2>&1 || true
    rm -f "$id_file"
    return 1
  fi

  echo "[$(date +%H:%M:%S)] Connected to $img ($ip), verifying cloud-init setup..." | tee -a "$log"
  local verify_out
  if verify_out=$(ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        "root@${ip}" "
          set -e
          WHO=\$(whoami)
          KEYS=\$(wc -l < /root/.ssh/authorized_keys | tr -d ' ')
          ROOT_PASS_STATUS=\$(passwd -S root 2>/dev/null | awk '{print \$2}' || grep '^root:' /etc/shadow | cut -d: -f2)
          SSHD_CHECK=\$(/usr/sbin/sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication) ' | tr '\n' ' ' || true)
          echo \"WHO=\$WHO | KEYS=\$KEYS | ROOT_PASS=\$ROOT_PASS_STATUS | SSHD=\$SSHD_CHECK\"
        " 2>>"$log"); then
    echo "PASS [$img]: $verify_out" | tee -a "$log"
  else
    echo "FAIL [$img]: Verification command failed" | tee -a "$log"
    linode-cli linodes delete "$lid" >>"$log" 2>&1 || true
    rm -f "$id_file"
    return 1
  fi

  echo "[$(date +%H:%M:%S)] Deleting $label (ID=$lid)..." | tee -a "$log"
  linode-cli linodes delete "$lid" >>"$log" 2>&1 || true
  rm -f "$id_file"
}

pids=()
idx=0
for img in "${IMAGE_LIST[@]}"; do
  region="${REGIONS[$((idx % ${#REGIONS[@]}))]}"
  idx=$((idx + 1))
  test_image "$img" "$region" &
  pids+=($!)
  sleep 0.5
done

fail_count=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail_count=$((fail_count + 1))
  fi
done

echo "=== SUMMARY ==="
grep -h -E "^(PASS|FAIL)" "$WORKDIR"/*.log | sort || true

exit "$fail_count"
