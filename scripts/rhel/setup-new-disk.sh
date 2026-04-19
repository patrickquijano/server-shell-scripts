#!/bin/sh
# Prompts to select an unpartitioned disk, creates a GPT partition with XFS
# filesystem, mounts it at a user-specified path, and adds a fstab entry for
# persistence across reboots.
# Usage: sh setup-new-disk.sh

set -e

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (use sudo)" >&2
  exit 1
fi

# Create a temporary file to store the list of unpartitioned disks
DISK_LIST=$(mktemp)
trap 'rm -f "$DISK_LIST"' EXIT

# List all block devices, filter for disks without partitions, and save to DISK_LIST
lsblk -dno NAME,SIZE,TYPE | while read -r name size type; do
  if [ "$type" = "disk" ]; then
    child_count=$(lsblk -lno NAME "/dev/$name" 2>/dev/null | wc -l)
    if [ "$child_count" -eq 1 ]; then
      printf '%s %s\n' "/dev/$name" "$size"
    fi
  fi
done >"$DISK_LIST"

# Check if any unpartitioned disks were found and prompt the user to select one
if [ ! -s "$DISK_LIST" ]; then
  echo "No unpartitioned disks found. Attach a new disk and try again." >&2
  exit 1
fi

# Display the list of available disks and prompt for selection
echo "Available unpartitioned disks:"
i=1
while IFS=' ' read -r disk size; do
  printf '  %d) %s  (%s)\n' "$i" "$disk" "$size"
  i=$((i + 1))
done <"$DISK_LIST"
TOTAL=$((i - 1))

# Prompt the user to select a disk by number
printf 'Select disk [1-%d]: ' "$TOTAL"
read -r SEL

# Validate the user's selection
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

# Read the selected disk and its size from DISK_LIST
DISK=$(awk -v n="$SEL" 'NR==n{print $1}' "$DISK_LIST")
DISK_SIZE=$(awk -v n="$SEL" 'NR==n{print $2}' "$DISK_LIST")

# Prompt the user for a mount point and validate it
printf 'Mount point (e.g. /mnt/data, /data, /srv/storage): '
read -r MOUNT_POINT

# Validate that the mount point is an absolute path starting with '/'
case "$MOUNT_POINT" in
/*) ;;
*)
  echo "Error: mount point must be an absolute path starting with '/'" >&2
  exit 1
  ;;
esac

# Check if the mount point is already in use
if grep -qs " $MOUNT_POINT " /proc/mounts; then
  echo "Error: '$MOUNT_POINT' is already in use as a mount point" >&2
  exit 1
fi

# Display a summary of the selected disk and mount point, and ask for confirmation
echo ""
echo "=== Summary ==="
printf 'Disk:         %s (%s)\n' "$DISK" "$DISK_SIZE"
printf 'Filesystem:   xfs\n'
printf 'Mount point:  %s\n' "$MOUNT_POINT"
echo ""
printf 'WARNING: This will ERASE ALL DATA on %s.\n' "$DISK"
printf 'Proceed? [y/N] '
read -r reply
case "$reply" in
[Yy]) ;;
*)
  echo "Aborted."
  exit 0
  ;;
esac

# Create a GPT partition table on the selected disk, create a single partition, and format it with XFS
echo ""
echo "Creating GPT partition table on $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart data 1MiB 100%
partprobe "$DISK"
udevadm settle

# Find the name of the new partition (e.g. /dev/sdb1) by listing the partitions on the disk and filtering out the disk itself
PART_NAME=$(lsblk -lno NAME "$DISK" | grep -v "^$(basename "$DISK")$" | head -n 1)
if [ -z "$PART_NAME" ]; then
  echo "Error: could not find new partition on $DISK" >&2
  exit 1
fi
PARTITION="/dev/$PART_NAME"

# Wait for the partition to be recognized by the system
echo "Formatting $PARTITION with XFS..."
mkfs.xfs "$PARTITION"

# Mount the new partition at the specified mount point and add an entry to /etc/fstab for persistence across reboots
echo "Mounting $PARTITION at $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
mount "$PARTITION" "$MOUNT_POINT"

# Get the UUID of the new partition and add an entry to /etc/fstab
UUID=$(blkid -s UUID -o value "$PARTITION")
if [ -z "$UUID" ]; then
  echo "Error: could not read UUID of $PARTITION" >&2
  exit 1
fi
echo "UUID=$UUID $MOUNT_POINT xfs defaults 0 0" | tee -a /etc/fstab >/dev/null
echo "Added to /etc/fstab (UUID=$UUID)"

# Display the status of the new disk, including the partition layout, mount point, and fstab entry
echo ""
echo "=== Disk Status ==="
lsblk "$DISK"
echo ""
df -h "$MOUNT_POINT"
echo ""
echo "fstab entry:"
grep "UUID=$UUID" /etc/fstab
echo ""
echo "Done. $PARTITION is mounted at $MOUNT_POINT and will persist across reboots."
