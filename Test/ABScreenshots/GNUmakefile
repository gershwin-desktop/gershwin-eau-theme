include $(GNUSTEP_MAKEFILES)/common.make

# Never let anything land in the LOCAL domain; nothing here is installed.
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

# abharness reuses the EauTest fixture and showcase sources from ../ so the
# captured windows are exactly the ones the showcase shows.  Not part of the
# Test/ build: run ./ab-compare.sh (see README.md).
APP_NAME = abharness
abharness_OBJC_FILES = abmain.m ../EauTest_main.m ../EauTestMenuBuilder.m \
	../EauTestWindowController.m ../EauTestFormBuilder.m ../EauTestListDataSource.m \
	../EauTestControlFactory.m ../EauMetricsChecker.m ../EauShowcaseSectionRegistry.m \
	../EauShowcaseWindowController.m ../EauShowcaseMetricsOverlayView.m
abharness_OBJCFLAGS += -fobjc-arc -fobjc-arc-exceptions
# The fixture's own main() is renamed so abmain.m can wrap it.
../EauTest_main.m_FILE_FLAGS += -Dmain=eau_orig_main
abharness_INCLUDE_DIRS += -I.. -I../..
abharness_GUI_LIBS += -lX11

TOOL_NAME = abinput
abinput_C_FILES = abinput.c
abinput_TOOL_LIBS += -lX11 -ldl

include $(GNUSTEP_MAKEFILES)/application.make
include $(GNUSTEP_MAKEFILES)/tool.make
