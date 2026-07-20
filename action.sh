#!/system/bin/sh

MODDIR=${0%/*}

sh "$MODDIR/scripts/force_system_webview.sh" --interactive --all
