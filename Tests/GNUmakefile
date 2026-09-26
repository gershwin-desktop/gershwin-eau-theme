include $(GNUSTEP_MAKEFILES)/common.make

# Tests of Eau's own (visual) code.  Units that moved to the behavior bundle
# (menu window filter, font substitution, menu scrolling, Menu PID scan) are
# tested in Behaviors/Tests.
TEST_TOOL_NAME = t_AlertPanelScrolling t_ButtonSpaceKey \
	t_ProgressStripes t_AlertPanelButtonRow t_SliderDisabled \
	t_RestartableTimer t_EauMetricsChecker t_EauShowcaseSectionRegistry \
	t_EauDrawerGeometry

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework

t_AlertPanelScrolling_OBJC_FILES = t_AlertPanelScrolling.m
t_ButtonSpaceKey_OBJC_FILES = t_ButtonSpaceKey.m
t_ProgressStripes_OBJC_FILES = t_ProgressStripes.m
t_AlertPanelButtonRow_OBJC_FILES = t_AlertPanelButtonRow.m
t_SliderDisabled_OBJC_FILES = t_SliderDisabled.m
t_RestartableTimer_OBJC_FILES = t_RestartableTimer.m
t_EauMetricsChecker_OBJC_FILES = t_EauMetricsChecker.m
t_EauShowcaseSectionRegistry_OBJC_FILES = t_EauShowcaseSectionRegistry.m
t_EauDrawerGeometry_OBJC_FILES = t_EauDrawerGeometry.m

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/test-tool.make
