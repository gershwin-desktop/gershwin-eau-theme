include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

# Theme-independent Gershwin behaviors: keyboard, modality, focus, menu
# tracking and Menu.app integration.  Loaded into every app through the
# GSAppKitUserBundles default (see README.md), so it works under any theme.
BUNDLE_NAME = GershwinBehaviors
BUNDLE_EXTENSION = .bundle
GershwinBehaviors_INSTALL_DIR = $(GNUSTEP_LIBRARY)/Bundles
GershwinBehaviors_PRINCIPAL_CLASS = GBBehaviors

# Wildcard so moving a behavior in or out needs no makefile edit.
GershwinBehaviors_OBJC_FILES = $(sort $(wildcard *.m))

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fobjc-arc-exceptions
ADDITIONAL_LDFLAGS += -lX11

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble
