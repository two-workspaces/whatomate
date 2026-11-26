#!/bin/sh
# Railway counts the kernel's cache of files the container has written or read as the
# service's memory, and with no memory pressure it is never freed: uploading or viewing
# 80 MB of images kept 86 MB "in use" on a 27 MB app. GNU dd's iflag=nocache drops a file's
# cached pages (posix_fadvise DONTNEED) without root, and the image has no Python for the
# drop-file-cache script our other templates use. Pages still being written are kept, so
# sync first.
sync
find "$@" -xdev -type f -exec dd if={} iflag=nocache count=0 status=none \; 2>/dev/null
exit 0
