################################################################################
#
# uvc-gadget (peterbay fork - used by showmewebcam)
# Provides -u <uvc-dev> -v <v4l2-dev> interface.
#
################################################################################

UVC_GADGET_VERSION = e9a733fe5c4a7fcb48e963e8d994bc33d24d814e
UVC_GADGET_SITE = https://github.com/peterbay/uvc-gadget.git
UVC_GADGET_SITE_METHOD = git
UVC_GADGET_LICENSE = GPL-2.0+
UVC_GADGET_LICENSE_FILES = LICENSE

define UVC_GADGET_BUILD_CMDS
	$(MAKE) CC="$(TARGET_CC)" LD="$(TARGET_LD)" -C $(@D)
endef

define UVC_GADGET_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/uvc-gadget $(TARGET_DIR)/usr/bin/uvc-gadget
endef

$(eval $(generic-package))