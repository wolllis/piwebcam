################################################################################
#
# uvc-gadget
#
################################################################################

UVC_GADGET_VERSION = v0.3.0
UVC_GADGET_SITE = git://git.ideasonboard.org/uvc-gadget.git
UVC_GADGET_SITE_METHOD = git
UVC_GADGET_LICENSE = LGPL-2.1+
UVC_GADGET_LICENSE_FILES = LICENSE
UVC_GADGET_INSTALL_STAGING = YES

# meson build system
UVC_GADGET_SUPPORTS_IN_SOURCE_BUILD = NO

# host-meson added automatically by meson-package infra
UVC_GADGET_DEPENDENCIES = libevent

# Disable -Werror since uvc-gadget v0.3.0 has a few harmless warnings
# with newer GCC (unused return value, transposed calloc args)
UVC_GADGET_CONF_OPTS = -Dwerror=false

$(eval $(meson-package))