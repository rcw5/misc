# Beyond Compare Quick Look macro.
# DATE: 30-Jan-16
#
# DESCRIPTION:
# Will open Finder and quicklook on the current selected image
# USAGE:
# Set up a macro to run the following command
# osascript ~/Desktop/OpenQuickLook.scpt '%f'

on run (arguments)
	tell application "Finder"
		activate
		reveal POSIX file (first item of arguments) as text
		delay 0.1
		tell application "System Events" to keystroke "y" using command down
	end tell
end run
