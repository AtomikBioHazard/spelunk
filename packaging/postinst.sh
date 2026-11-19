#!/bin/sh
# SPDX-License-Identifier: MIT
# Package post-install script. It only prints the next step: it never touches home directories,
# because a system package must not change per-user state.
set -e

if [ "$1" = "configure" ]; then
  echo "Spelunk installed. Run 'spelunk-setup' as your normal user to finish setup."
fi

exit 0
