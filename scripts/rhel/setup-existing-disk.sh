#!/bin/sh
# Prompts to select a partition that already has a filesystem but is not
# currently mounted, mounts it at a user-specified path, and adds a fstab entry
# for persistence across reboots.
# Usage: sudo sh setup-existing-disk.sh

set -e

# Create a temporary file to store mountable partitions.
PART_LIST=$(mktemp)
trap 'rm -f "$PART_LIST"' EXIT

# List partitions with filesystems that are currently not mounted.
lsblk -lnpo NAME,SIZE,TYPE,FSTYPE | while read -r part size type fstype; do
  if [ "$type" = "part" ] && [ -n "$fstype" ]; then
    if grep -qs "^$part " /proc/mounts; then
      continue
    fi

    uuid=$(sudo blkid -s UUID -o value "$part" 2>/dev/null || true)
    if [ -n "$uuid" ]; then
      printf '%s %s %s %s\n' "$part" "$size" "$fstype" "$uuid"
    fi
  fi
done >"$PART_LIST"

# Check if any eligible partitions were found.
if [ ! -s "$PART_LIST" ]; then
  echo "No unmounted partitions with an existing filesystem were found." >&2
  exit 1
fi

# Display the list of available partitions and prompt for selection.
echo "Available unmounted partitions with filesystems:"
i=1
while IFS=' ' read -r part size fstype uuid; do
  printf '  %d) %s  (%s, %s, UUID=%s)\n' "$i" "$part" "$size" "$fstype" "$uuid"
  i=$((i + 1))
done <"$PART_LIST"
TOTAL=$((i - 1))

printf 'Select partition [1-%d]: ' "$TOTAL"
read -r SEL

# Validate the selected index.
case "$SEL" in
'' | *[!0-9]*)
  echo "Error: '$SEL' is not a valid number" >&2
  exit 1
  ;;
esac
if [ "$SEL" -lt 1 ] || [ "$SEL" -gt "$TOTAL" ]; then
  echo "Error: selection must be between 1 and $TOTAL" >&2
  exit 1
fi

# Read selected partition details.
PARTITION=$(awk -v n="$SEL" 'NR==n{print $1}' "$PART_LIST")
PART_SIZE=$(awk -v n="$SEL" 'NR==n{print $2}' "$PART_LIST")
FS_TYPE=$(awk -v n="$SEL" 'NR==n{print $3}' "$PART_LIST")
UUID=$(awk -v n="$SEL" 'NR==n{print $4}' "$PART_LIST")

# Ensure the partition still exists.
if [ ! -b "$PARTITION" ]; then
  echo "Error: selected partition '$PARTITION' is no longer available" >&2
  exit 1
fi

# Abort if a matching fstab entry already exists.
if grep -qs "^[^#].*UUID=${UUID}[[:space:]]" /etc/fstab; then
  echo "Error: /etc/fstab already contains an entry for UUID=$UUID" >&2
  exit 1
fi
if grep -qs "^[^#]*[[:space:]]${PARTITION}[[:space:]]" /etc/fstab; then
  echo "Error: /etc/fstab already contains an entry for $PARTITION" >&2
  exit 1
fi

# Prompt for mount point and validate.
printf 'Mount point (e.g. /mnt/data, /data, /srv/storage): '
read -r MOUNT_POINT

case "$MOUNT_POINT" in
/*) ;;
*)
  echo "Error: mount point must be an absolute path starting with '/'" >&2
  exit 1
  ;;
esac

if grep -qs " $MOUNT_POINT " /proc/mounts; then
  echo "Error: '$MOUNT_POINT' is already in use as a mount point" >&2
  exit 1
fi
if grep -qs "^[^#].*[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab; then
  echo "Error: /etc/fstab already contains an entry for mount point '$MOUNT_POINT'" >&2
  exit 1
fi

# Display summary and require confirmation before mounting.
echo ""
echo "=== Summary ==="
printf 'Partition:    %s (%s)\n' "$PARTITION" "$PART_SIZE"
printf 'Filesystem:   %s\n' "$FS_TYPE"
printf 'UUID:         %s\n' "$UUID"
printf 'Mount point:  %s\n' "$MOUNT_POINT"
echo ""
printf 'This will mount %s without formatting or erasing data.\n' "$PARTITION"
printf 'Proceed? [y/N] '
read -r reply
case "$reply" in
[Yy]) ;;
*)
  echo "Aborted."
  exit 0
  ;;
esac

# Mount the selected partition and persist in fstab.
echo ""
echo "Mounting $PARTITION at $MOUNT_POINT..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount -t "$FS_TYPE" "$PARTITION" "$MOUNT_POINT"

echo "UUID=$UUID $MOUNT_POINT $FS_TYPE defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
echo "Added to /etc/fstab (UUID=$UUID)"

# Display status output after mounting.
echo ""
echo "=== Disk Status ==="
lsblk "$PARTITION"
echo ""
df -h "$MOUNT_POINT"
echo ""
echo "fstab entry:"
grep "UUID=$UUID" /etc/fstab
echo ""
echo "Done. $PARTITION is mounted at $MOUNT_POINT and will persist across reboots."
