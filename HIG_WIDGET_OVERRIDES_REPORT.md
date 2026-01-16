# Eau HIG Widget Override Decisions

This report lists every UI widget/class implemented in libs-gui and whether the Eau theme overrides it for HIG compliance.
Decisions reflect HIG sizing/spacing guidance (control heights, stacked spacing, dialog separators) and whether GSTheme or class categories already enforce those.

## Covered (override already present)

These are enforced either by GSTheme overrides or class/category overrides in the theme.

- NSAlert — NSPanel dialog normalization
- NSBox — class/category override
- NSBrowser — GSTheme override
- NSBrowserCell — class/category override
- NSButtonCell — class/category override
- NSClipView — class/category override
- NSColorPanel — NSPanel dialog normalization
- NSColorWell — GSTheme override
- NSComboBox — class/category override
- NSComboBoxCell — class/category override
- NSDatePicker — class/category override
- NSDatePickerCell — class/category override
- NSFontPanel — NSPanel dialog normalization
- NSForm — class/category override
- NSFormCell — class/category override
- NSHelpPanel — NSPanel dialog normalization
- NSImageCell — class/category override
- NSImageView — class/category override
- NSLevelIndicator — class/category override
- NSLevelIndicatorCell — class/category override
- NSMatrix — class/category override
- NSMenu — GSTheme override
- NSMenuItemCell — class/category override
- NSMenuView — class/category override
- NSOpenPanel — NSPanel dialog normalization
- NSOutlineView — class/category override
- NSPageLayout — NSPanel dialog normalization
- NSPanel — NSPanel dialog normalization
- NSPathCell — class/category override
- NSPathComponentCell — class/category override
- NSPathControl — class/category override
- NSPopUpButton — class/category override
- NSPopUpButtonCell — class/category override
- NSPrintPanel — NSPanel dialog normalization
- NSProgressIndicator — GSTheme override
- NSSavePanel — NSPanel dialog normalization
- NSScrollView — GSTheme override
- NSScroller — GSTheme override
- NSSearchFieldCell — class/category override
- NSSecureTextFieldCell — class/category override
- NSSliderCell — class/category override
- NSSplitView — class/category override
- NSStepperCell — class/category override
- NSTabView — GSTheme override
- NSTableCellView — class/category override
- NSTableHeaderCell — class/category override
- NSTableHeaderView — class/category override
- NSTableView — GSTheme override
- NSTextFieldCell — class/category override
- NSTextView — class/category override
- NSTokenFieldCell — class/category override
- NSWindow — class/category override

## No override needed

These either inherit sizing from their cells/containers or are HIG-neutral in the theme context.

- NSButton
- NSRulerMarker
- NSRulerView
- NSSearchField
- NSSecureTextField
- NSSlider
- NSStatusBar
- NSStepper
- NSTabViewItem
- NSTableColumn
- NSTableRowView
- NSText
- NSTextField
- NSTokenField
- NSToolbar

## Needs override

No remaining widgets require additional overrides at this stage; coverage above enforces HIG sizes and dialog styling.
