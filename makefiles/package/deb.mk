ifeq ($(_THEOS_PACKAGE_FORMAT_LOADED),)
_THEOS_PACKAGE_FORMAT_LOADED := 1

_THEOS_PLATFORM_DPKG_DEB ?= dm.pl
_THEOS_PLATFORM_DPKG_DEB_COMPRESSION ?= $(or $(THEOS_PLATFORM_DEB_COMPRESSION_TYPE),lzma)
ifeq ($(_THEOS_FINAL_PACKAGE),$(_THEOS_TRUE))
THEOS_PLATFORM_DEB_COMPRESSION_LEVEL ?= 9
else
THEOS_PLATFORM_DEB_COMPRESSION_LEVEL ?= 1
endif

_THEOS_DEB_PACKAGE_CONTROL_PATH := $(or $(wildcard $(THEOS_PROJECT_DIR)/control),$(wildcard $(THEOS_LAYOUT_DIR)/DEBIAN/control))
_THEOS_DEB_CAN_PACKAGE := $(call __exists,$(_THEOS_DEB_PACKAGE_CONTROL_PATH))
_THEOS_PACKAGE_INC_VERSION_PREFIX := -
_THEOS_PACKAGE_EXTRA_VERSION_PREFIX := +

_THEOS_DEB_HAS_DPKG_DEB := $(call __executable,$(_THEOS_PLATFORM_DPKG_DEB))

ifneq ($(_THEOS_DEB_HAS_DPKG_DEB),$(_THEOS_TRUE))
internal-package-check::
	$(ERROR_BEGIN)"$(MAKE) package requires $(_THEOS_PLATFORM_DPKG_DEB)."$(ERROR_END)
endif

ifeq ($(_THEOS_DEB_CAN_PACKAGE),$(_THEOS_TRUE)) # Control file found
THEOS_PACKAGE_NAME := $(shell grep -i "^Package:" "$(_THEOS_DEB_PACKAGE_CONTROL_PATH)" | cut -d' ' -f2-)
THEOS_PACKAGE_ARCH := $(shell grep -i "^Architecture:" "$(_THEOS_DEB_PACKAGE_CONTROL_PATH)" | cut -d' ' -f2-)

ifeq ($(THEOS_PACKAGE_SCHEME)-$(THEOS_PACKAGE_ARCH),rootless-iphoneos-arm)
	# Override architecture
	THEOS_PACKAGE_ARCH := iphoneos-arm64
else ifeq ($(THEOS_PACKAGE_SCHEME)-$(THEOS_PACKAGE_ARCH),roothide-iphoneos-arm)
	# Override architecture
	THEOS_PACKAGE_ARCH := iphoneos-arm64e
else ifeq ($(THEOS_PACKAGE_SCHEME)-$(THEOS_PACKAGE_ARCH),roothide-iphoneos-arm64)
	# Override architecture
	THEOS_PACKAGE_ARCH := iphoneos-arm64e
endif

THEOS_PACKAGE_BASE_VERSION := $(shell grep -i "^Version:" "$(_THEOS_DEB_PACKAGE_CONTROL_PATH)" | cut -d' ' -f2-)

$(THEOS_STAGING_DIR)/DEBIAN:
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"$(ECHO_END)
ifeq ($(_THEOS_HAS_STAGING_LAYOUT),1) # If we have a layout directory, copy layout/DEBIAN to the staging directory.
	$(ECHO_NOTHING)[ -d "$(THEOS_LAYOUT_DIR)/DEBIAN" ] && rsync -a "$(THEOS_LAYOUT_DIR)/DEBIAN/" "$(THEOS_STAGING_DIR)/DEBIAN" $(_THEOS_RSYNC_EXCLUDE_COMMANDLINE) || true$(ECHO_END)
endif # _THEOS_HAS_STAGING_LAYOUT

_TARGET_SWIFT_VERSION_GE_5_0 = $(call __simplify,_TARGET_SWIFT_VERSION_GE_5_0,$(call __vercmp,$(_THEOS_TARGET_SWIFT_VERSION),ge,5.0))

ifeq ($(_TARGET_SWIFT_VERSION_GE_5_0),)
_THEOS_DEB_LIBSWIFT_PACKAGE := com.modmyi.libswift4
_THEOS_DEB_LIBSWIFT_PACKAGE_VERSION := $(_THEOS_TARGET_SWIFT_VERSION)
else
_THEOS_DEB_LIBSWIFT_PACKAGE := org.swift.libswift
# Note: This only needs to be changed if a newer package is released.
# See how _THEOS_TARGET_DEFAULT_OS_DEPLOYMENT_VERSION is set for more info.
_THEOS_DEB_LIBSWIFT_PACKAGE_VERSION := 5.0
endif

_THEOS_DEB_LIBSWIFT_DEPENDS := $(_THEOS_DEB_LIBSWIFT_PACKAGE) (>= $(_THEOS_DEB_LIBSWIFT_PACKAGE_VERSION))

_THEOS_DEB_ORION_DEPENDS := dev.theos.orion (>= 1.0.0)

$(THEOS_STAGING_DIR)/DEBIAN/control: $(THEOS_STAGING_DIR)/DEBIAN
	$(ECHO_NOTHING)sed -e 's/\$${LIBSWIFT}/$(_THEOS_DEB_LIBSWIFT_DEPENDS)/g; s/\$${LIBSWIFT_VERSION}/$(_THEOS_DEB_LIBSWIFT_PACKAGE_VERSION)/g; s/\$${ORION}/$(_THEOS_DEB_ORION_DEPENDS)/g; /^[Vv]ersion:/d; /^[Aa]rchitecture:/d; /^$$/d; $$G; P; D' "$(_THEOS_DEB_PACKAGE_CONTROL_PATH)" > "$@"$(ECHO_END)
	$(ECHO_NOTHING)echo "Architecture: $(THEOS_PACKAGE_ARCH)" >> "$@"$(ECHO_END)
	$(ECHO_NOTHING)echo "Version: $(_THEOS_INTERNAL_PACKAGE_VERSION)" >> "$@"$(ECHO_END)
	$(ECHO_NOTHING)echo "Installed-Size: $(shell du $(_THEOS_PLATFORM_DU_EXCLUDE) DEBIAN -ks "$(THEOS_STAGING_DIR)" | cut -f 1)" >> "$@"$(ECHO_END)

before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control

_THEOS_DEB_PACKAGE_FILENAME = $(THEOS_PACKAGE_DIR)/$(THEOS_PACKAGE_NAME)_$(_THEOS_INTERNAL_PACKAGE_VERSION)_$(THEOS_PACKAGE_ARCH).deb

internal-package::
# Use additional tmp stage for package schemes
# Iterate through staging dir and move top-level items to tmp stage if != "DEBIAN"
# Move the parent directory (i.e., package install prefix), which now contains project files, back to the main stage
ifneq ($(THEOS_PACKAGE_INSTALL_PREFIX),)
	$(eval _STAGE_CONTENTS := $(wildcard $(THEOS_STAGING_DIR)/*))
	$(eval _STAGE_STATE := $(lastword $(subst /, ,$(_STAGE_CONTENTS)))$(words $(_STAGE_CONTENTS)))
	$(eval _DEBIAN_ONLY := $(if $(filter DEBIAN1,$(_STAGE_STATE)),$(_THEOS_TRUE),$(_THEOS_FALSE)))
# Only bother with tmp stage if there are top-level items
	$(if $(_DEBIAN_ONLY),, \
		$(foreach i,$(_STAGE_CONTENTS), \
			$(if $(findstring DEBIAN,$(i)),, \
				$(shell mv $(i) $(_THEOS_SCHEME_STAGE)) \
			) \
		) \
		$(shell mv $(wildcard $(_THEOS_STAGING_TMP)/*) $(THEOS_STAGING_DIR)) \
	)
endif
	$(ECHO_NOTHING)COPYFILE_DISABLE=1 $(FAKEROOT) -r $(_THEOS_PLATFORM_DPKG_DEB) -Z$(_THEOS_PLATFORM_DPKG_DEB_COMPRESSION) -z$(THEOS_PLATFORM_DEB_COMPRESSION_LEVEL) -b "$(THEOS_STAGING_DIR)" "$(_THEOS_DEB_PACKAGE_FILENAME)"$(ECHO_END)

# This variable is used in package.mk
after-package:: __THEOS_LAST_PACKAGE_FILENAME = $(_THEOS_DEB_PACKAGE_FILENAME)

else # _THEOS_DEB_CAN_PACKAGE == 0
internal-package::
	$(ERROR_BEGIN)"$(MAKE) package requires you to have a control file either in the layout/DEBIAN/ directory or in the project root. The control is used to determine info about the package (e.g., name, arch, and version)."$(ERROR_END)

endif # _THEOS_DEB_CAN_PACKAGE
endif # _THEOS_PACKAGE_FORMAT_LOADED
