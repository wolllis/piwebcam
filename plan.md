# Plan: Buildroot custom image for Raspberry Pi USB Webcam

## TL;DR
Build a minimal Buildroot-based Linux image for a Raspberry Pi that boots, captures video from the HQ Camera Module (IMX477) via CSI-2, and exposes itself as a UVC-compliant USB webcam device using the Linux UVC gadget driver. The Pi enumerates as a standard webcam when plugged into a host PC — no special drivers needed.

## Architecture & Key Decisions

- **Target board**: Raspberry Pi Zero 2 W (RP3A0/BCM2837, quad Cortex-A53, 512MB RAM)
- **Build system**: Buildroot 2026.05 from scratch on x86_64 host
- **Init system**: BusyBox init (minimal footprint)
- **C library**: glibc (Bootlin external toolchain) — switched from musl
- **Kernel**: Raspberry Pi fork (bcm2709_defconfig + custom fragment) via github tarball
- **Camera pipeline**: Direct V4L2 (kernel bcm2835-unicam + imx477 driver) → uvc-gadget → UVC function → USB host. No libcamera — fewer dependencies, more robust on limited hardware.
- **Userspace**: `uvc-gadget` (reference tool from freedesktop.org) to bridge camera frames to UVC function

## Steps

### Phase 1: Project Scaffolding ✅

1. **Create project directory structure** inside `/home/martin/raspberry_pi/`: a br2-external tree with board support files ✅
   - `br2-external/` root with `external.desc`, `Config.in`, `external.mk`
   - `br2-external/configs/rpi2w_webcam_defconfig`
   - `br2-external/board/raspberrypi/rpi2w/` with kernel config fragment, rootfs overlay, post-image script, init scripts

2. **Clone Buildroot** into `buildroot/` subdirectory — use git tag `2026.05` ✅

### Phase 2: Buildroot Configuration ✅

3. **Target architecture**: `BR2_arm=y`, `BR2_cortex_a53=y`, Bootlin glibc external toolchain ✅

4. **Kernel**: RPi fork, bcm2709_defconfig + fragment ✅
   - Kernel config enables: `CONFIG_USB_CONFIGFS`, `CONFIG_USB_CONFIGFS_F_UVC`, `CONFIG_USB_DWC2=y`, `CONFIG_USB_DWC2_DUAL_ROLE=y`, `CONFIG_CMA_SIZE_MBYTES=256`, `CONFIG_I2C_BCM2835=y`, `CONFIG_PWM_BCM2835=y`
   - `bcm2835-unicam` and `imx477` built as modules (=m) — loaded at boot by init script
   - `dwc_otg` (Pi proprietary host driver) kept enabled alongside `dwc2` — boot-time overlay swaps to dwc2 for peripheral mode

5. **Bootloader**: Raspberry Pi firmware (`BR2_PACKAGE_RPI_FIRMWARE=y`) ✅

6. **Filesystem**: ext4 ~120MB ✅

7. **Essential packages**: uvc-gadget (v0.3.0, br2-external), libevent ✅

### Phase 3: Camera + UVC Integration ✅

8. **config.txt**: Enables camera, CMA=256, dwc2 overlay with dr_mode=peripheral, disable-bt for UART serial ✅

9. **Init script** (`S99uvc-webcam`): At boot, loads camera modules, waits for /dev/video0, configures UVC gadget via configfs, then runs `uvc-gadget` to bridge camera frames to UVC function ✅

10. **Rootfs overlay**: config.txt, cmdline.txt, S99uvc-webcam ✅

### Phase 4: Build & Validation

11. **Initial build**: ✅ Completed (serial works, root login works)

12. **USB gadget debugging**: 🔄 IN PROGRESS
    - Problem: `dwc_otg` (host-only driver) claims USB hardware, preventing gadget mode
    - First fix: Disabled dwc_otg → kernel had no USB driver at all (broke everything)
    - **Current approach**: Both dwc_otg (host) and dwc2 (dual-role) built-in. `dtoverlay=dwc2,dr_mode=peripheral` in config.txt swaps driver at boot.
    - Overlays now copied to FAT partition by post-image.sh (fixes dtoverlay loading)
    - Kernel built with correct config (CONFIG_USB_DWCOTG=y + CONFIG_USB_DWC2=y + CONFIG_USB_DWC2_DUAL_ROLE=y)
    - **Needs testing**: flash image, verify dmesg for dwc2 bind, UDC detection, /dev/video*, host enumeration

13. **Test**: Flash `sdcard.img` to SD card, boot Pi, connect USB OTG to host PC. Verify `lsusb` shows UVC device.

## Verification
1. ✅ Build completes without errors
2. ✅ SD card boots on Raspberry Pi (serial console working)
3. ⬜ `lsusb` on Pi shows USB gadgets enumerated
4. ⬜ On host PC: `lsusb` shows "Linux UVC gadget" or similar
5. ⬜ Host can open the webcam in Chrome/Teams/`ffplay /dev/video0` — video streams from HQ Camera

## Known Issues
### dwc_otg vs dwc2 conflict
The Raspberry Pi kernel fork uses `dwc_otg` (proprietary host-only driver) which claims the USB controller before dwc2 can bind in peripheral mode. The `dtoverlay=dwc2,dr_mode=peripheral` in config.txt should swap the driver at boot. This works on standard Raspberry Pi OS but hasn't been verified with Buildroot.

### Camera drivers as modules
`bcm2835-unicam` and `imx477` are modules (=m) because MEDIA_SUPPORT=m forces them. They're loaded by S99uvc-webcam at boot. The `camera_auto_detect=1` in config.txt may not work without the firmware sensor autodetection path — the init script handles this explicitly.

## Relevant files
- `br2-external/configs/rpi2w_webcam_defconfig` — Buildroot defconfig
- `br2-external/board/raspberrypi/rpi2w/linux.config` — kernel config fragment
- `br2-external/board/raspberrypi/rpi2w/rootfs-overlay/etc/init.d/S99uvc-webcam` — UVC gadget init script
- `br2-external/board/raspberrypi/rpi2w/rootfs-overlay/boot/config.txt` — Pi firmware config
- `br2-external/board/raspberrypi/rpi2w/genimage.cfg` — SD card image generation
- `br2-external/board/raspberrypi/rpi2w/post-image.sh` — post-image script for genimage

## Decisions
- Using **br2-external tree** to keep all customization outside Buildroot source
- Using **BusyBox init** for minimal footprint
- **libcamera** as optional — can fall back to direct V4L2 if libcamera is too heavy for Pi's 512MB RAM
- UVC gadget configured via configfs at boot, not compiled into kernel defconfig
- Camera sensor driver (IMX477) needs to be in kernel, plus bcm2835-unicam for CSI-2 capture
- `dtoverlay=dwc2,dr_mode=peripheral` for USB gadget mode (instead of disabling dwc_otg in kernel config)
- Overlays copied to FAT partition via mtools in post-image.sh (Buildroot's rpi-firmware post-install puts them in a subdirectory)

## Further Considerations
1. **Which exact Pi model?** "Raspberry Pi 2 W" is ambiguous. Options:
   - **Raspberry Pi Zero 2 W** (RP3A0, Cortex-A53, 512MB RAM) — has OTG USB, can act as device
   - **Raspberry Pi 2 Model B V1.2** (BCM2837, Cortex-A53, 1GB RAM) — has 4x USB ports via LAN9515 hub, OTG is on the SoC but may need microUSB OTG cable
   
   The Zero 2 W is better suited for a UVC gadget since it has a dedicated OTG microUSB port. The Pi 2 Model B's USB port goes through a hub/LAN chip which complicates gadget mode.

2. **libcamera vs direct V4L2**: libcamera adds ~15MB and complexity. For webcam use, direct V4L2 with `uvc-gadget` may be simpler and smaller, using the kernel's bcm2835-unicam + imx477 driver directly.

3. **Frame size**: Pi 2 / Zero 2 W has limited USB bandwidth. 720p@15fps MJPEG is realistic. 1080p may need significant tuning.