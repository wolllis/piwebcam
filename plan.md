# Plan: Buildroot custom image for Raspberry Pi USB Webcam

## TL;DR
Build a minimal Buildroot-based Linux image for a Raspberry Pi that boots, captures video from the HQ Camera Module (IMX477) via CSI-2, and exposes itself as a UVC-compliant USB webcam device using the Linux UVC gadget driver. The Pi enumerates as a standard webcam when plugged into a host PC — no special drivers needed.

## Architecture & Key Decisions

- **Target board**: Raspberry Pi Zero 2 W (BCM2710A1/RP3A0, quad Cortex-A53, 512MB RAM)
- **Build system**: Buildroot 2026.08-git, br2-external in `br2-external/`, build in `buildroot/`
- **Build command**: `make -C buildroot BR2_EXTERNAL=../br2-external`
- **Init system**: BusyBox init (minimal footprint), mdev for device management
- **C library**: glibc — Bootlin armv7-eabihf bleeding-edge toolchain (headers 5.15, required by libcamera-apps ≥5.5)
- **Kernel**: RPi Linux fork, `bcm2709_defconfig` + custom fragment, kernel 6.12.61-v7
- **Camera pipeline**: IMX477 (CSI-2) → `bcm2835-unicam-legacy` → libcamera RPi/vc4 pipeline → `bcm2835-isp` → `rpicam-vid` → `v4l2loopback /dev/video10` → `uvc-gadget` → USB UVC
- **Userspace tools**: `rpicam-vid` (libcamera-apps v1.7.0), `uvc-gadget` (peterbay fork), `v4l2loopback`

## Steps

### Phase 1: Project Scaffolding ✅

1. **Create br2-external tree** ✅
   - `br2-external/` with `external.desc` (name: RPI2W_WEBCAM), `Config.in`, `external.mk`
   - `br2-external/configs/rpi2w_webcam_defconfig`
   - `br2-external/board/raspberrypi/rpi2w/` — kernel fragment, rootfs overlay, post-image script

2. **Buildroot** cloned into `buildroot/` ✅

### Phase 2: Buildroot Configuration ✅

3. **Toolchain**: Bootlin armv7-eabihf glibc bleeding-edge (headers 5.15) ✅
   - Stable toolchain (headers 5.4) was tried first but failed — libcamera-apps requires ≥5.5

4. **Kernel**: RPi fork, `bcm2709_defconfig` + fragment ✅
   - Fragment adds: `USB_GADGET=y`, `USB_CONFIGFS_F_UVC=y`, `USB_DWC2=y`, `USB_DWC2_DUAL_ROLE=y`, `I2C_BCM2835=y`, `PWM_BCM2835=y`, `REGULATOR=y`, `REGULATOR_FIXED_VOLTAGE=y`, `CMA_SIZE_MBYTES=256`
   - `I2C_MUX_PINCTRL=m` — needed for camera I2C bus (i2c0mux), loaded explicitly in init script
   - Camera drivers as modules: `bcm2835-unicam-legacy`, `imx477`, `bcm2835-isp`, `v4l2loopback`
   - USB gadget built-in: `USB_GADGET=y`, `USB_LIBCOMPOSITE=y`, `USB_F_UVC=y`, `USB_DWC2=y`

5. **Packages**: `libcamera` (RPi/vc4 pipeline), `libcamera-apps`, `v4l2loopback`, `libv4l`, `libv4l-utils`, `rpi-firmware` ✅

6. **uvc-gadget**: peterbay fork in `br2-external/package/uvc-gadget/` ✅

7. **Filesystem**: ext4 256MB ✅

### Phase 3: Camera + UVC Integration ✅

8. **config.txt** (`br2-external/board/raspberrypi/rpi2w/config.txt`):
   ```
   start_file=start.elf
   fixup_file=fixup.dat
   kernel=zImage
   gpu_mem_512=128
   dtoverlay=imx477
   dtoverlay=dwc2,dr_mode=peripheral
   dtoverlay=disable-bt
   dtoverlay=disable-wifi
   enable_uart=1
   ```
   - `start.elf` only — `start_x.elf` hangs; `camera_auto_detect=1` also hangs
   - `dtoverlay=imx477` (no `cam0` — Pi Zero 2 W camera connector is CSI1, the overlay's default)

9. **Init script** (`S99uvc-webcam`) — 5-stage pipeline:
   - Stage 1: load modules (`i2c-mux-pinctrl`, `bcm2835-unicam-legacy`, `imx477`, `bcm2835-isp`, `v4l2loopback`)
   - Stage 2: wait for V4L2 subdev (sensor bind)
   - Stage 3: launch `rpicam-vid --codec mjpeg -o /dev/video10`
   - Stage 4: configure UVC gadget via configfs
   - Stage 5: start `uvc-gadget` bridging `/dev/video10` → UVC

10. **post-image.sh**: Assembles `boot.vfat` + `sdcard.img`; injects overlays from rpi-firmware into FAT via mtools ✅

### Phase 4: Build & Debugging ✅ (build complete, hardware debugging in progress)

11. **Build**: `make -C buildroot BR2_EXTERNAL=../br2-external` ✅ — all binaries present: `rpicam-vid` (114K), `uvc-gadget` (57K), `v4l2loopback.ko` (61K)

12. **Hardware debugging** (all resolved):

    | # | Symptom | Root cause | Fix |
    |---|---------|-----------|-----|
    | 1 | `rpicam-vid` missing | Stable toolchain headers 5.4 < 5.5 required by libcamera-apps | Switch to bleeding-edge toolchain (headers 5.15) |
    | 2 | `start_x.elf` hangs | Incompatible with our firmware+kernel combo | Use `start.elf` only |
    | 3 | `camera_auto_detect=1` hangs | Firmware autodetect incompatible | Use explicit `dtoverlay=imx477` |
    | 4 | `bcm2835-unicam` (new) doesn't bind | Driver `unicam` doesn't match DT node with imx477 overlay | Use `bcm2835-unicam-legacy` instead |
    | 5 | imx477 loads but sensor not found (no I2C device) | `i2c-mux-pinctrl.ko` never loaded — mdev has no modalias rule; without it `i2c0mux` has no driver and `i2c@1` (i2c_csi_dsi) is never created | Add `modprobe i2c-mux-pinctrl` as first camera module in init script |
    | 6 | `rpicam-vid` crashes: "Overwriting Request::controls() is not allowed" | `controls_` in `rpicam_app.cpp` initialized with global `controls::controls` infoMap; libcamera v0.7.1 `Camera::queueRequest()` checks that `request->controls().infoMap() == &camera_->controls()` — they never match | Patch: reinitialize `controls_` with `libcamera::ControlList(camera_->controls())` after `camera_->acquire()`. Patch in `br2-external/patches/libcamera-apps/0001-fix-controls-infomap-mismatch.patch`, applied via `BR2_GLOBAL_PATCH_DIR` |
    | 7 | UVC gadget setup fails: `streaming/class/fs/h` symlink fails | `create_streaming_header_links` called in `$(...)` subshell; `_log→printf` writes to stdout, so INFO lines were captured into `$hdr` alongside `header/h`; `header_path` became garbage | Replace echo/`$()` pattern with global `_HEADER_NODE` variable — no subshell |

### Phase 5: End-to-end Validation 🔄 IN PROGRESS

13. **Full pipeline confirmed working** on hardware (`/tmp/webcam.log` — boot T+21s):
    - Stage 1 ✅ — all modules loaded (i2c-mux-pinctrl, bcm2835-unicam-legacy, imx477, bcm2835-isp, v4l2loopback)
    - Stage 2 ✅ — `v4l-subdev0: [imx477 10-001a]` present; subdev wait times out but libcamera finds it anyway
    - Stage 3 ✅ — `rpicam-vid` (PID 446) streaming MJPEG 640×480@30 to `/dev/video10`
    - Stage 4 ✅ — UVC gadget configured via configfs, bound to UDC `3f980000.usb`
    - Stage 5 ✅ — `uvc-gadget` (PID 615) bridging `/dev/video10` → `/dev/video2` (UVC)

14. **Host enumeration confirmed** ✅ — Windows sees the UVC device.

15. **Current blocker — VS endpoint -61 (ENODATA)**:
    - When host opens the webcam, kernel logs `uvc: VS request completed with status -61`
    - uvc-gadget log is empty; error doesn't recover
    - MMAL firmware timeout cascade after ~800s (secondary effect)
    - Root cause not yet confirmed; need: uvc-gadget log, /dev/video10 format, /dev/video2 format, dmesg context

## Verification
1. ✅ Build completes without errors
2. ✅ SD card boots (kernel 6.12.61-v7, serial console ttyAMA0 115200)
3. ✅ All modules load (i2c-mux-pinctrl, bcm2835-unicam-legacy, imx477, bcm2835-isp, v4l2loopback)
4. ✅ IMX477 sensor probes (`v4l-subdev0: [imx477 10-001a]`)
5. ✅ libcamera detects camera (`/base/soc/i2c0mux/i2c@1/imx477@1a`, pipeline rpi/vc4)
6. ✅ `rpicam-vid` starts and streams to `/dev/video10` (after controls_ infoMap fix)
7. ✅ UVC gadget configured via configfs and bound to UDC `3f980000.usb`
8. ✅ `uvc-gadget` running, bridging `/dev/video10` → `/dev/video2` (USB UVC device)
9. ⬜ Host PC sees UVC webcam device (`lsusb`)
10. ⬜ Video streams to host application

## Key Files
| File | Purpose |
|------|---------|
| `br2-external/configs/rpi2w_webcam_defconfig` | Buildroot defconfig |
| `br2-external/board/raspberrypi/rpi2w/linux.config` | Kernel config fragment |
| `br2-external/board/raspberrypi/rpi2w/config.txt` | Pi firmware config |
| `br2-external/board/raspberrypi/rpi2w/rootfs-overlay/etc/init.d/S99uvc-webcam` | Main init script |
| `br2-external/board/raspberrypi/rpi2w/post-image.sh` | Image assembly |
| `br2-external/package/uvc-gadget/uvc-gadget.mk` | peterbay uvc-gadget package |
| `br2-external/patches/libcamera-apps/0001-fix-controls-infomap-mismatch.patch` | rpicam-apps ControlInfoMap fix |

## Known Constraints
- `start_x.elf` hangs — use `start.elf` only
- `camera_auto_detect=1` hangs — use explicit `dtoverlay=imx477`
- `bcm2835-unicam` (new broadcom/ driver) doesn't bind with imx477 overlay — use `bcm2835-unicam-legacy`
- `i2c-mux-pinctrl` must be loaded explicitly (mdev has no modalias rules)
- libcamera v0.7.1 + rpicam-apps v1.7.0 have a ControlInfoMap mismatch bug (patched)
- MJPEG encoding is software on Zero 2 W (no MMAL hardware encoder); 640×480@30fps should be feasible

## Further Considerations
- **Frame size**: 640×480@30fps MJPEG is the initial target. 720p is possible; 1080p may be too slow for SW encoding on the Zero 2 W's quad A53.
- **USB bandwidth**: High-speed USB (480Mbps) supports MJPEG at 1080p; the bottleneck is SW encoding speed.