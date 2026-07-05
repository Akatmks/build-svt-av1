#!/usr/bin/env fish


# `clang-cl` is broken when running in GitHub Actions and either the profiling run fails, or the final binary doesn't work. Using `clang` and `clang++` for now.
# TODO: Test and migrate to MCF Gthread.


argparse "static=" "shared=" "pgo-parameters=" "base-arch-only=" "dovi-hdr10plus=" "ffms2=" "cmakeflags=" "cflags-profiling=" "ldflags-profiling=" "cflags-final=" "ldflags-final=" -- $argv
or return $status

set -g flag_static $_flag_static
set -g flag_shared $_flag_shared
set -g flag_pgo_parameters $_flag_pgo_parameters
set -g flag_base_arch_only $_flag_base_arch_only
set -g flag_dovi_hdr10plus $_flag_dovi_hdr10plus
set -g flag_ffms2 $_flag_ffms2
set -g flag_cmakeflags $_flag_cmakeflags
set -g flag_cflags_profiling $_flag_cflags_profiling
set -g flag_ldflags_profiling $_flag_ldflags_profiling
set -g flag_cflags_final $_flag_cflags_final
set -g flag_ldflags_final $_flag_ldflags_final

echo "[build-svt-av1] Init"
echo $flag_static
echo $flag_shared
echo $flag_pgo_parameters
echo $flag_base_arch_only
echo $flag_dovi_hdr10plus
echo $flag_ffms2
echo $flag_cmakeflags
echo $flag_cflags_profiling
echo $flag_ldflags_profiling
echo $flag_cflags_final
echo $flag_ldflags_final


# $argv[1]: static: "static", "shared"
# $argv[2]: PGO: "profiling", "final"
function parameters_base
    if begin test $argv[1] != "static" ; and test $argv[1] != "shared"; end
        echo "[parameters_base] unexpected argv[1]: $argv[1]"
    end
    if begin test $argv[2] != "profiling" ; and test $argv[2] != "final"; end
        echo "[parameters_base] unexpected argv[2]: $argv[2]"
    end

    set -g cmake_command
    set -g cflags
    set -g ldflags

    set -g -a cmake_command cmake --fresh -B svt_build -G Ninja -DCMAKE_BUILD_TYPE=Release
    if test $argv[1] = "static"
        set -g -a cmake_command -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=ON
    else
        set -g -a cmake_command -DBUILD_SHARED_LIBS=ON -DBUILD_APPS=ON
    end
    set -g -a cmake_command -DTHREADS_PREFER_PTHREAD_FLAG=OFF -DCMAKE_USE_WIN32_THREADS_INIT=ON -DENABLE_AVX512=ON -DSVT_AV1_LTO=OFF

    set -g -a ldflags -fuse-ld=lld

    if test $flag_dovi_hdr10plus != "false"
        set -g -a cflags -DLIBDOVI_FOUND=1 -DLIBHDR10PLUS_RS_FOUND=1 (pkg-config --cflags --static --dont-define-prefix dovi_tool/BuildAction/lib/pkgconfig/dovi.pc) (pkg-config --cflags --static --dont-define-prefix hdr10plus_tool/BuildAction/lib/pkgconfig/hdr10plus-rs.pc)
        set -g -a ldflags (pkg-config --libs --static --dont-define-prefix dovi_tool/BuildAction/lib/pkgconfig/dovi.pc) (pkg-config --libs --static --dont-define-prefix hdr10plus_tool/BuildAction/lib/pkgconfig/hdr10plus-rs.pc)
    end
    set -g -a cflags -DNDEBUG -O3 -fno-exceptions -fno-rtti -fno-stack-protector -fno-sanitize=all -fno-dwarf2-cfi-asm -Wno-deprecated
    set -g -a cflags $cflags_arch
    if test $argv[2] = "profiling"
        set -g -a cflags -flto=full -fwhole-program-vtables
        set -g -a ldflags -flto=full -fwhole-program-vtables
    else
        set -g -a cflags -flto=full -fwhole-program-vtables -fvisibility=hidden -fvisibility-inlines-hidden
        set -g -a ldflags -flto=full -fwhole-program-vtables -fvisibility=hidden -fvisibility-inlines-hidden
    end
    if test $argv[2] = "profiling"
        set -g -a cflags -fprofile-generate=PGO -ftemporal-profile
    else
        set -g -a cflags -fprofile-use=(cygpath -m -a PGO/default.profdata)
    end
    if test $argv[2] = "profiling"
        set -g -a cflags $flag_cflags_profiling
        set -g -a ldflags $flag_ldflags_profiling
    else
        set -g -a cflags $flag_cflags_final
        set -g -a ldflags $flag_ldflags_final
    end
end
# $argv[1]: static: "static", "shared"
# $argv[2]: PGO: "profiling", "final"
function parameters_icelake_server_znver5
    set -g cflags_arch -march=icelake-server -mtune=znver5 -mprefer-vector-width=512
    parameters_base $argv[1] $argv[2]
end
function parameters_znver2
    set -g cflags_arch -march=znver2 -mtune=znver2
    parameters_base $argv[1] $argv[2]
end
function parameters_x86_64_v3_znver2
    set -g cflags_arch -march=x86-64-v3 -mtune=znver2 -mno-gather
    parameters_base $argv[1] $argv[2]
end

function build
    set cmake_command $cmake_command -DCMAKE_C_FLAGS_RELEASE="$cflags" -DCMAKE_CXX_FLAGS_RELEASE="$cflags" -DCMAKE_EXE_LINKER_FLAGS_RELEASE="$ldflags" $flag_cmakeflags
    echo $cmake_command
    $cmake_command
    and ninja -v -C svt_build
    or return $status
end


# $argv[1]: directory string: "icelake-server+znver5", "znver2", "x86-64-v3+znver2"
function pgo_build
    set -g parameters parameters_(string replace --all - _ (string replace --all + _ $argv[1]))

    set prof_files PGO/*.profraw PGO/*.profdata
    rm -rf svt_build Build $prof_files
    or return $status
    ls PGO

    echo "[build-svt-av1] Profiling building $argv[1]"
    $parameters static profiling
    build
    or return $status

    echo "[build-svt-av1] Profiling $argv[1]"
    eval Bin/Release/SvtAv1EncApp -i PGO/PGO.y4m -b /dev/null --preset 2 $flag_pgo_parameters
    or return $status
    llvm-profdata merge -o PGO/default.profdata PGO/*.profraw
    or return $status
    ls PGO

    mkdir -p BuildAction/$argv[1]
    or return $status
    if test $flag_static != "false"
        rm -rf svt_build Build
        or return $status

        echo "[build-svt-av1] Final building static $argv[1]"
        $parameters static final
        build
        or return $status

        cp -r Bin/Release BuildAction/$argv[1]/static
        or return $status

        echo "[build-svt-av1] Final static $argv[1]"
        lld BuildAction/$argv[1]/static/SvtAv1EncApp
        BuildAction/$argv[1]/static/SvtAv1EncApp --help | grep dolby
        or return $status
        BuildAction/$argv[1]/static/SvtAv1EncApp --help | grep hdr10plus
        or return $status
        eval BuildAction/$argv[1]/static/SvtAv1EncApp -i PGO/PGO.y4m -b /dev/null $flag_pgo_parameters --preset 4
        or return $status

        echo "[build-svt-av1] Result static $argv[1]"
        find BuildAction/$argv[1]/static -name "*"
    end
    if test $flag_shared != "false"
        rm -rf svt_build Build
        or return $status

        echo "[build-svt-av1] Final building shared $argv[1]"
        $parameters shared final
        build
        or return $status

        cp -r Bin/Release BuildAction/$argv[1]/shared
        or return $status

        echo "[build-svt-av1] Final shared $argv[1]"
        lld BuildAction/$argv[1]/shared/SvtAv1EncApp
        BuildAction/$argv[1]/shared/SvtAv1EncApp --help | grep dolby
        or return $status
        BuildAction/$argv[1]/shared/SvtAv1EncApp --help | grep hdr10plus
        or return $status
        eval BuildAction/$argv[1]/shared/SvtAv1EncApp -i PGO/PGO.y4m -b /dev/null $flag_pgo_parameters --preset 4
        or return $status

        echo "[build-svt-av1] Result shared $argv[1]"
        find BuildAction/$argv[1]/shared -type f
    end
end


if test $flag_base_arch_only != "true"
    pgo_build icelake-server+znver5
    pgo_build znver2
end
pgo_build x86-64-v3+znver2
or return $status
