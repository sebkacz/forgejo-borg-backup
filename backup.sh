#!/bin/sh

export BORG_REPO=/path/to/backup/forgejo
export BORG_PASSPHRASE="my very secure passphrase"
SOURCE_DIR=/path/to/forgejo
NTFY="https://:<my_token>@<ntfy_instance>/<ntfy_topic>"

NODE1_USER="<user>"
NODE1_IP="<tailscale ip/fqdn>"

# Make sure Forgejo is up if something went wrong
cleanup() {
  if [ "$(docker inspect -f '{{.State.Running}}' forgejo 2>/dev/null)" != "true" ]; then
    echo "Bringing Forgejo back up..."
    docker start forgejo >/dev/null 2>&1
    FORGEJO_UP=$(date +%s)
    FORGEJO_TIME=$(( $FORGEJO_UP - $FORGEJO_DOWN ))
    curl -d "Forgejo was down for $FORGEJO_TIME seconds" \
    -H "p:2" \
    $NTFY
  fi
}
trap cleanup EXIT

# Start
curl -d "Backup starting at: $(date)" \
-H "t: Taking Forgejo offline for backup" \
$NTFY
    
echo "Stopping Forgejo..."
FORGEJO_DOWN=$(date +%s)
if ! DOCKER_OUTPUT=$(docker stop forgejo 2>&1); then
  curl -d "$DOCKER_OUTPUT" \
  -H "t: Failed to stop Forgejo container" \
  -H "ta:x" \
  -H "p:5" \
  $NTFY
  exit 1
fi

# Check we can compress the backup, and run it with zstd at a decent ratio
echo "Creating local Borg backup..."
if ! BORG_OUTPUT=$(borg create --compression auto,zstd,12 --stats -v ::$(date +%Y-%m-%d) $SOURCE_DIR 2>&1); then
  curl -d "$BORG_OUTPUT" \
  -H "t: Borg creation failed" \
  -H "ta:x" \
  -H "p:5" \
  $NTFY
  exit 1
else
  curl -d "$BORG_OUTPUT" \
  -H "t: Borg creation completed" \
  $NTFY
fi

echo "Starting Forgejo..."
if ! DOCKER_OUTPUT=$(docker start forgejo 2>&1); then
  curl -d "$DOCKER_OUTPUT" \
  -H "t: Failed to start up Forgejo container" \
  -H "ta:x" \
  -H "p:5" \
  $NTFY
  exit 1
fi

FORGEJO_UP=$(date +%s)
FORGEJO_TIME=$(( $FORGEJO_UP - $FORGEJO_DOWN ))
curl -d "Forgejo was down for $FORGEJO_TIME seconds" \
  -H "p:2" \
  $NTFY

# Only keep a daily backup for a week, then once a week for a month, then monthly for half a year
# Adjust this to taste
echo "Pruning local backups..."
BORG_PRUNE=$(borg prune --list -s --keep-daily=7 --keep-weekly=4 --keep-monthly=6 2>&1)
curl -d "$BORG_PRUNE" \
  -H "t: Borg prune completed"
  -H "p:2" \
  $NTFY

echo "Compacting repo..."
borg compact

# Copy this section for more remote servers
echo "Syncing to <remote server name>"
if rsync -az --delete "$BORG_REPO/" "$NODE1_USER@$NODE1_IP:$BORG_REPO/"; then
  NODE1_STATUS="<remote server name> Sync: Success"
else
  NODE1_STATUS="<remote server name> Sync: Failed"
  FAILED=1
fi

# Add the copy status to the ntfy notification
if [ -z "$FAILED" ]; then
  curl -d "$NODE1_STATUS" \
  -H "t: Forgejo backup completed" \
  -H "ta:white_check_mark" \
  -H "p:3" \
  $NTFY
else
  curl -d "$NODE1_STATUS" \
  -H "t: Forgejo backup finished with errors" \
  -H "ta:warning" \
  -H "p:4" \
  $NTFY
fi

# Time how long it took for the backup to complete
DONE=$(date +%s)
COMPLETION_TIME=$(( $DONE - $FORGEJO_DOWN ))
curl -d "Backup task took $(date -d@$COMPLETION_TIME +%H:%M:%S )" \
-H "t: Backup completed" \
$NTFY
