#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

IMGID="$(dd if="${IMG_FILE}" skip=440 bs=1 count=4 2>/dev/null | xxd -e | cut -f 2 -d' ')"

BOOT_PARTUUID="${IMGID}-01"
CRYPT_ROOT_PARTUUID="${IMGID}-02"
ROOT_DEV="/dev/mapper/${CRYPT_ROOT_NAME}"

sed -i "s#BOOTDEV#PARTUUID=${BOOT_PARTUUID}#" "${ROOTFS_DIR}/etc/fstab"
sed -i "s#ROOTDEV#${ROOT_DEV}#" "${ROOTFS_DIR}/etc/fstab"

sed -i "s#CRYPT_ROOT_NAME#${CRYPT_ROOT_NAME}#" "${ROOTFS_DIR}/etc/crypttab"
sed -i "s#CRYPT_ROOT_DEV#PARTUUID=${CRYPT_ROOT_PARTUUID}#" "${ROOTFS_DIR}/etc/crypttab"

sed -i "s#ROOTDEV#${ROOT_DEV}#" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
sed -i "s#CRYPT_ROOT_NAME#${CRYPT_ROOT_NAME}#" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
sed -i "s#CRYPT_ROOT_DEV#PARTUUID=${CRYPT_ROOT_PARTUUID}#" "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
