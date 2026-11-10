#!/bin/sh

export BORG_REPO=/path/to/backup/forgejo
export BORG_PASSPHRASE="my very secure passphrase"
NTFY="https://:<my_token>@<ntfy_instance>/<ntfy_topic>"

NODE1_USER="<user>"
NODE1_IP="<tailscale ip/fqdn>"

START=$(date +%s)
echo "Checking local repository..."
if ! BORG_OUTPUT=$(borg check --verify-data -v 2>&1); then
  curl -d "$BORG_OUTPUT" \
  -H "t: Local repo failed verification" \
  -H "ta:x" \
  -H "p:5" \
  $NTFY
else
  curl -d "$BORG_OUTPUT" \
  -H "t: Local repo passed verification" \
  -H "ta:white_check_mark" \
  $NTFY
fi

echo "Checking <remote server name> repository..."
if ! BORG_OUTPUT=$(borg check --verify-data -v "$NODE1_USER@$NODE1_IP:$BORG_REPO" 2>&1); then
  curl -d "$BORG_OUTPUT" \
  -H "t: <remote server name> repo failed verification" \
  -H "ta:x" \
  -H "p:5" \
  $NTFY
else
  curl -d "$BORG_OUTPUT" \
  -H "t: <remote server name> repo passed verification" \
  -H "ta:white_check_mark" \
  $NTFY
fi

DONE=$(date +%s)
COMPLETION_TIME=$(( $DONE - $START ))
TIME=$(printf '%02dh:%02dm:%02ds\n' $((COMPLETION_TIME/3600)) $((COMPLETION_TIME%3600/60)) $((COMPLETION_TIME%60)))
curl -d "Verification task took $TIME" \
-H "t: Verification completed" \
$NTFY
