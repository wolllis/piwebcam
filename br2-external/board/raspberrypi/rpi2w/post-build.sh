#!/bin/sh

set -u
set -e

# Add a console on tty1 (HDMI)
if [ -e ${TARGET_DIR}/etc/inittab ]; then
    grep -qE '^tty1::' ${TARGET_DIR}/etc/inittab || \
        sed -i '/GENERIC_SERIAL/a\
tty1::respawn:/sbin/getty -L  tty1 0 vt100 # HDMI console' ${TARGET_DIR}/etc/inittab

    # Expose serial login on both possible UART mappings.
    grep -qE '^ttyAMA0::' ${TARGET_DIR}/etc/inittab || \
        sed -i '/GENERIC_SERIAL/a\
ttyAMA0::respawn:/sbin/getty -L  ttyAMA0 115200 vt100 # PL011 serial console' ${TARGET_DIR}/etc/inittab

    grep -qE '^ttyS0::' ${TARGET_DIR}/etc/inittab || \
        sed -i '/GENERIC_SERIAL/a\
ttyS0::respawn:/sbin/getty -L  ttyS0 115200 vt100 # mini-UART serial console' ${TARGET_DIR}/etc/inittab
fi