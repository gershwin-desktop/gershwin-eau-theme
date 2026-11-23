include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

PACKAGE_NAME = Eau
BUNDLE_NAME = Eau
BUNDLE_EXTENSION = .theme
VERSION = 1

Eau_INSTALL_DIR=$(GNUSTEP_LIBRARY)/Themes
Eau_PRINCIPAL_CLASS = Eau

# Wildcard so moving code between Eau and Behaviors/ needs no list edit.
Eau_OBJC_FILES = $(sort $(wildcard *.m))

ADDITIONAL_TOOL_LIBS =
ADDITIONAL_OBJCFLAGS += -fobjc-arc -fobjc-arc-exceptions
ADDITIONAL_LDFLAGS += -lX11
$(BUNDLE_NAME)_RESOURCE_FILES = \
	./Resources/ThemeIcon.png\
	./Resources/ThemePreview.png\
	./Resources/ThemeImages\
	./Resources/ThemeTiles\
	./Resources/*.clr
include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

