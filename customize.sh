#!/system/bin/sh

SKIPUNZIP=0

ui_print "- Force System WebView"
ui_print "- KernelSU WebUI entry: webroot/index.html"
ui_print "- Setting executable permissions"

set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/scripts/force_system_webview.sh" 0 0 0755

ui_print "- Installation complete"
