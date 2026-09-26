include $(GNUSTEP_MAKEFILES)/common.make

# Manual test for window-modal sheets: a document window with sheet
# buttons plus an independent window that must keep working meanwhile.
#   openapp ./SheetTest.app                  interactive
#   openapp ./SheetTest.app -autotest YES    scripted checks, exits 0/1
# Load the bundle under test with
#   -GSAppKitUserBundles '("<path>/GershwinBehaviors.bundle")'
APP_NAME = SheetTest
SheetTest_OBJC_FILES = main.m

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fobjc-arc-exceptions

include $(GNUSTEP_MAKEFILES)/application.make
