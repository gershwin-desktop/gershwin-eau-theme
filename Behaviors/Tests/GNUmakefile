include $(GNUSTEP_MAKEFILES)/common.make

TEST_TOOL_NAME = t_GBMenuSafeTriangle t_GBMenuWindowFilter t_GBFontSubstitution \
	t_GBMenuOverflowScale t_GBMenuPIDScanMemory

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework

t_GBMenuSafeTriangle_OBJC_FILES = t_GBMenuSafeTriangle.m
t_GBMenuWindowFilter_OBJC_FILES = t_GBMenuWindowFilter.m
t_GBFontSubstitution_OBJC_FILES = t_GBFontSubstitution.m
t_GBMenuOverflowScale_OBJC_FILES = t_GBMenuOverflowScale.m
t_GBMenuPIDScanMemory_OBJC_FILES = t_GBMenuPIDScanMemory.m

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/test-tool.make
