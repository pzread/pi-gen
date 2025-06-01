#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

BOOT_SIZE="$((512 * 1024 * 1024))"
ROOT_SIZE=$(du -x --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot/firmware --block-size=1 | cut -f 1)

# All partition sizes and starts will be aligned to this size
ALIGN="$((8 * 1024 * 1024))"
# Add this much space to the calculated file size. This allows for
# some overhead (since actual space usage is usually rounded up to the
# filesystem block size) and gives some free space on the resulting
# image.
ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

BOOT_PART_START=$((ALIGN))
BOOT_PART_SIZE=$(((BOOT_SIZE + ALIGN - 1) / ALIGN * ALIGN))
ROOT_PART_START=$((BOOT_PART_START + BOOT_PART_SIZE))
ROOT_PART_SIZE=$(((ROOT_SIZE + ROOT_MARGIN + ALIGN  - 1) / ALIGN * ALIGN))
IMG_SIZE=$((BOOT_PART_START + BOOT_PART_SIZE + ROOT_PART_SIZE + ALIGN))

truncate -s "${IMG_SIZE}" "${IMG_FILE}"

parted --script "${IMG_FILE}" mklabel gpt
parted --script "${IMG_FILE}" unit B mkpart FIRMWARE fat32 "${BOOT_PART_START}" "$((BOOT_PART_START + BOOT_PART_SIZE - 1))"
parted --script "${IMG_FILE}" unit B mkpart CRYPTROOT ext4 "${ROOT_PART_START}" "$((ROOT_PART_START + ROOT_PART_SIZE - 1))"

echo "Creating loop device..."
cnt=0
until ensure_next_loopdev && LOOP_DEV="$(losetup --show --find --partscan "$IMG_FILE")"; do
	if [ $cnt -lt 5 ]; then
		cnt=$((cnt + 1))
		echo "Error in losetup.  Retrying..."
		sleep 5
	else
		echo "ERROR: losetup failed; exiting"
		exit 1
	fi
done

ensure_loopdev_partitions "$LOOP_DEV"
BOOT_DEV="${LOOP_DEV}p1"
CRYPTROOT_DEV="${LOOP_DEV}p2"
ROOT_DEV="/dev/mapper/${CRYPTROOT_NAME}"

ROOT_FEATURES="^huge_file"
for FEATURE in 64bit; do
if grep -q "$FEATURE" /etc/mke2fs.conf; then
	ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
fi
done

if [ "$BOOT_SIZE" -lt 134742016 ]; then
	FAT_SIZE=16
else
	FAT_SIZE=32
fi

mkdosfs -n bootfs -F "$FAT_SIZE" -s 4 -v "$BOOT_DEV" > /dev/null

cryptsetup luksFormat --type luks2 "${CRYPTROOT_DEV}"
cryptsetup open "${CRYPTROOT_DEV}" "${CRYPTROOT_NAME}"
mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null

mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
mkdir -p "${ROOTFS_DIR}/boot/firmware"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot/firmware" -t vfat

rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot/firmware "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/firmware/" "${ROOTFS_DIR}/boot/firmware/"

BOOT_PARTUUID="$(blkid -s PARTUUID -o value "${BOOT_DEV}")"
CRYPTROOT_PARTUUID="$(blkid -s PARTUUID -o value "${CRYPTROOT_DEV}")"

sed -i "s#BOOTDEV#PARTUUID=${BOOT_PARTUUID}#" "${ROOTFS_DIR}/etc/fstab"
sed -i "s#ROOTDEV#${ROOT_DEV}#" "${ROOTFS_DIR}/etc/fstab"

sed -i "s#CRYPTROOT_NAME#${CRYPTROOT_NAME}#" "${ROOTFS_DIR}/etc/crypttab"
sed -i "s#CRYPTROOT_DEV#PARTUUID=${CRYPTROOT_PARTUUID}#" "${ROOTFS_DIR}/etc/crypttab"

sed -i "s#ROOTDEV#${ROOT_DEV}#" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
sed -i "s#CRYPTROOT_NAME#${CRYPTROOT_NAME}#" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
sed -i "s#CRYPTROOT_DEV#PARTUUID=${CRYPTROOT_PARTUUID}#" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
