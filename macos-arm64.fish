#!/usr/bin/env fish

argparse "static" "shared" "base-arch-only" "dovi-hdr10plus" "ffms2" "cmakeflags=" "cflags-profiling=" "cxxflags-profiling=" "ldflags-profiling=" "cflags-final=" "cxxflags-final=" "ldflags-final=" -- $argv
or return 1
