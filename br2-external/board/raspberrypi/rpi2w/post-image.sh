#!/bin/bash
#
# post-image.sh - Raspberry Pi Zero 2 W UVC Webcam
# Generates genimage config and runs it to produce the SD card image
#

set -e

BOARD_DIR="$(dirname "$0")"
BOARD_NAME="$(basename "${BOARD_DIR}")"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# Copy firmware files to BINARIES_DIR root so they land at the root
# of the FAT partition (where the Pi firmware expects them)
cp "${BINARIES_DIR}/rpi-firmware/config.txt" "${BINARIES_DIR}/config.txt"
cp "${BINARIES_DIR}/rpi-firmware/cmdline.txt" "${BINARIES_DIR}/cmdline.txt"
cp "${BINARIES_DIR}/rpi-firmware/start.elf" "${BINARIES_DIR}/start.elf"
cp "${BINARIES_DIR}/rpi-firmware/fixup.dat" "${BINARIES_DIR}/fixup.dat"
cp "${BINARIES_DIR}/rpi-firmware/bootcode.bin" "${BINARIES_DIR}/bootcode.bin"

# Copy overlay dtbos so dtoverlay= directives work
# Overlays go in overlays/ subdirectory on FAT partition
rm -rf "${BINARIES_DIR}/overlays"
cp -a "${BINARIES_DIR}/rpi-firmware/overlays" "${BINARIES_DIR}/overlays"

# Generate genimage config
GENIMAGE_CFG="${BINARIES_DIR}/genimage.cfg"

cat > "${GENIMAGE_CFG}" << EOF
image boot.vfat {
    vfat {
        files = {
EOF

# Add individual boot files
for f in config.txt cmdline.txt start.elf fixup.dat bootcode.bin zImage; do
    echo "            \"${f}\"," >> "${GENIMAGE_CFG}"
done

# Add .dtb files
for f in "${BINARIES_DIR}"/*.dtb; do
    echo "            \"$(basename "${f}")\"," >> "${GENIMAGE_CFG}"
done

cat >> "${GENIMAGE_CFG}" << 'EOF'
        }
    }
    size = 64M
}

image sdcard.img {
    hdimage {
    }

    partition boot {
        partition-type = 0xC
        bootable = "true"
        image = "boot.vfat"
    }

    partition rootfs {
        partition-type = 0x83
        image = "rootfs.ext4"
    }
}
EOF

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

rm -rf "${GENIMAGE_TMP}"

genimage \
    --rootpath "${ROOTPATH_TMP}"   \
    --tmppath "${GENIMAGE_TMP}"    \
    --inputpath "${BINARIES_DIR}"  \
    --outputpath "${BINARIES_DIR}" \
    --config "${GENIMAGE_CFG}"

# Copy overlay dtbos onto the FAT partition using host mtools
# genimage doesn't support subdirectories in vfat files list
MTOOLS_SKIP_CHECK=1 "${HOST_DIR}/bin/mmd" -i "${BINARIES_DIR}/boot.vfat" "::overlays" 2>/dev/null || true
for f in "${BINARIES_DIR}"/overlays/*.dtbo; do
    MTOOLS_SKIP_CHECK=1 "${HOST_DIR}/bin/mcopy" -sp -i "${BINARIES_DIR}/boot.vfat" "${f}" "::overlays/"
done

# Keep sdcard.img in sync with updated boot.vfat content.
# The boot partition starts at sector 1 (512 bytes), so write boot.vfat at offset 512.
dd if="${BINARIES_DIR}/boot.vfat" of="${BINARIES_DIR}/sdcard.img" bs=512 seek=1 conv=notrunc status=none

exit $?