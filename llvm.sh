#!/bin/bash

# This is needed because of some weird WSL issue
# related to files losing executable bit when edited
# from outside WSL subsystem.

chmod +x ./_LLVM.sh
./_LLVM.sh "$@"
