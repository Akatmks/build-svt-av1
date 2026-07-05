#!/usr/bin/env fish


# For some reason manually specifying `-flto` is broken and doesn't link, so using `-DSVT_AV1_LTO=ON` for now


argparse "static=" "shared=" "pgo-parameters=" "base-arch-only=" "dovi-hdr10plus=" "ffms2=" "cmakeflags=" "cflags-profiling=" "ldflags-profiling=" "cflags-final=" "ldflags-final=" -- $argv
or return $status

echo "[build-svt-av1] Init"
echo $_flag_static
echo $_flag_shared
echo $_flag_pgo_parameters
echo $_flag_base_arch_only
echo $_flag_dovi_hdr10plus
echo $_flag_ffms2
echo $_flag_cmakeflags
echo $_flag_cflags_profiling
echo $_flag_ldflags_profiling
echo $_flag_cflags_final
echo $_flag_ldflags_final
