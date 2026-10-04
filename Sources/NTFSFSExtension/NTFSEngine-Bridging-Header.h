// Add Scripts/install-dependencies.sh's ntfs-3g-mac install prefix to this
// target's HEADER_SEARCH_PATHS and LIBRARY_SEARCH_PATHS, e.g.:
//   /usr/local/opt/ntfs-3g-mac/include   (Intel Homebrew)
//   /opt/homebrew/opt/ntfs-3g-mac/include (Apple Silicon Homebrew)
// and link against libntfs-3g.dylib from that same prefix's lib/ directory.
//
// This is the line that actually links GPLv2 object code into the
// extension's binary — see README.md "Driver nativo" section before
// shipping anything built against this header.
#include <ntfs-3g/volume.h>
#include <ntfs-3g/inode.h>
#include <ntfs-3g/attrib.h>
#include <ntfs-3g/dir.h>
