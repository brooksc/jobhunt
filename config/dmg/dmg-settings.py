# dmgbuild settings for the JobHunt DMG (TASK-566).
#
# Builds the styled "drag to Applications" installer window WITHOUT driving Finder via AppleScript —
# dmgbuild writes the .DS_Store layout directly, so it works on a headless CI runner (create-dmg's
# AppleScript path fails there with "-1743 Not authorized to send Apple events to Finder").
#
# Paths are taken from the environment so the workflow can point at the freshly-built app and the
# multi-resolution background TIFF:
#   DMG_APP         path to Jobhunt.app          (default: build/export-dmg/Jobhunt.app)
#   DMG_BACKGROUND  path to background image      (default: config/dmg/background.tiff)
import os.path

app_path = os.environ.get("DMG_APP", "build/export-dmg/Jobhunt.app")
app_name = os.path.basename(app_path)  # "Jobhunt.app"

# Contents of the disk image: the app plus an /Applications symlink to drag onto.
files = [app_path]
symlinks = {"Applications": "/Applications"}

# Compressed read-only image (same format the previous hdiutil step produced).
format = "UDZO"

# Background art. A multi-res TIFF (1x + 2x via tiffutil) keeps it crisp on Retina and fills the
# window on standard displays. The window content is sized to the 1x art (640x400 pt).
background = os.environ.get("DMG_BACKGROUND", "config/dmg/background.tiff")

# Window: position on screen + content size (points). Matches background.png (640x400).
window_rect = ((200, 120), (640, 400))
default_view = "icon-view"

# Clean installer look — no toolbar / sidebar / status / path bars.
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
# Positions match the arrow in the background: app on the left, Applications on the right.
icon_locations = {
    app_name: (160, 186),
    "Applications": (480, 186),
}
