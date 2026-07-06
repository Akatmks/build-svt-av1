#!/usr/bin/env fish

# To build SVT-AV1 yourself, always use clang over gcc or msvc, and ideally LLVM project's clang over other variants of clang. It's plain faster.
# Run `Build/linux/build.sh --native --static --release --enable-lto --enable-pgo` to build a decent binary.
# For more optimised builds, check how we do it below. Everything here is not selected on a whim but tested to indeed produce a faster binary.
# Thanks to studies and contributions from afed, Emre, Ironclad, Itachi Uchiha, Khaoklong, Miss Ashenlight, Soda, SwareJonge, Trix, Yiss, and other people in the community for discovering the method to build the fastest binary.


argparse "os=" "arch=" "static=" "shared=" "pgo-parameters=" "base-arch-only=" "dovi-hdr10plus=" "ffms2=" "cmakeflags=" "cflags-profiling=" "ldflags-profiling=" "cflags-final=" "ldflags-final=" -- $argv
or return $status

set -g os $_flag_os
set -g arch $_flag_arch
set -g flag_static $_flag_static
set -g flag_shared $_flag_shared
eval set -g flag_pgo_parameters $_flag_pgo_parameters
set -g flag_base_arch_only $_flag_base_arch_only
set -g flag_dovi_hdr10plus $_flag_dovi_hdr10plus
set -g flag_ffms2 $_flag_ffms2
eval set -g flag_cmakeflags $_flag_cmakeflags
eval set -g flag_cflags_profiling $_flag_cflags_profiling
eval set -g flag_ldflags_profiling $_flag_ldflags_profiling
eval set -g flag_cflags_final $_flag_cflags_final
eval set -g flag_ldflags_final $_flag_ldflags_final

echo "[build-svt-av1] Init"
echo os: $os
echo arch: $arch
echo flag_static: $flag_static
echo flag_shared: $flag_shared
echo flag_pgo_parameters: $flag_pgo_parameters
echo flag_base_arch_only: $flag_base_arch_only
echo flag_dovi_hdr10plus: $flag_dovi_hdr10plus
echo flag_ffms2: $flag_ffms2
echo flag_cmakeflags: $flag_cmakeflags
echo flag_cflags_profiling: $flag_cflags_profiling
echo flag_ldflags_profiling: $flag_ldflags_profiling
echo flag_cflags_final: $flag_cflags_final
echo flag_ldflags_final: $flag_ldflags_final


# $argv[1]: static: "static", "shared"
# $argv[2]: PGO: "profiling", "final"
function parameters_base
    if begin test $argv[1] != "static" ; and test $argv[1] != "shared" ; end
        echo "[parameters_base] unexpected argv[1]: $argv[1]"
    end
    if begin test $argv[2] != "profiling" ; and test $argv[2] != "final" ; end
        echo "[parameters_base] unexpected argv[2]: $argv[2]"
    end

    set -g cmake_command
    set -g cflags
    set -g ldflags

    # executable
    if test $os = "macOS"
        if test $arch = "ARM64"
            set -f homebrew_llvm_prefix /opt/homebrew/opt/llvm
        else
            set -f homebrew_llvm_prefix /usr/local/opt/llvm
        end
        fish_add_path -g -p $homebrew_llvm_prefix/bin
    end
    set -g -a cmake_command cmake --fresh -B svt_build -G Ninja
    # [Windows] `clang-cl` is broken when running in GitHub Actions and either the profiling run fails, or the final binary doesn't work. Using `clang` and `clang++` for now.
    set -g -a cmake_command -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
    set -g -a ldflags -fuse-ld=lld
    if test $os = "macOS"
        set -g -a cmake_command -DCMAKE_PREFIX_PATH=$homebrew_llvm_prefix -DCMAKE_AR=$homebrew_llvm_prefix/bin/llvm-ar -DCMAKE_RANLIB=$homebrew_llvm_prefix/bin/llvm-ranlib -DCMAKE_C_STANDARD_LIBRARIES=$homebrew_llvm_prefix/lib -DCMAKE_CXX_STANDARD_LIBRARIES=$homebrew_llvm_prefix/lib -DCMAKE_C_STANDARD_INCLUDE_DIRECTORIES=$homebrew_llvm_prefix/include -DCMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES=$homebrew_llvm_prefix/include
        set -g -a cflags -I$homebrew_llvm_prefix/include -D_LIBCPP_DISABLE_AVAILABILITY
        set -g -a ldflags -L$homebrew_llvm_prefix/lib -L$homebrew_llvm_prefix/lib/c++ -L$homebrew_llvm_prefix/lib/unwind -lunwind
    end
    
    # base
    if test $argv[1] = "static"
        set -g -a cmake_command -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=ON
    else
        set -g -a cmake_command -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_APPS=ON
    end
    if test $os = "Windows"
        # [Windows] TODO: Test and migrate to MCF Gthread.
        set -g -a cmake_command -DTHREADS_PREFER_PTHREAD_FLAG=OFF -DCMAKE_USE_WIN32_THREADS_INIT=ON
    end
    set -g -a cflags -DNDEBUG -O3 -fno-exceptions -fno-rtti -fno-stack-protector -fno-sanitize=all -fno-dwarf2-cfi-asm -Wno-deprecated
    if test $os = "Linux"
        set -g -a cflags -fno-semantic-interposition -fno-stack-clash-protection -fno-pic -fno-pie
        set -g -a ldflags -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections -Wl,--icf=all -Wl,--strip-all -Wl,-z,norelro -Wl,--build-id=none -Wl,--relax -Wl,-z,noseparate-code -Wl,-znow
    else if test $os = "macOS"
        set -g -a ldflags -Wl,-O3
    end

    # dovi hdr10+
    if test $flag_dovi_hdr10plus != "false"
        if test $os != "Linux"
            set -g -a cflags -DLIBDOVI_FOUND=1 -DLIBHDR10PLUS_RS_FOUND=1 (pkg-config --cflags --static --dont-define-prefix dovi_tool/BuildAction/lib/pkgconfig/dovi.pc) (pkg-config --cflags --static --dont-define-prefix hdr10plus_tool/BuildAction/lib/pkgconfig/hdr10plus-rs.pc)
            set -g -a ldflags (pkg-config --libs --static --dont-define-prefix dovi_tool/BuildAction/lib/pkgconfig/dovi.pc) (pkg-config --libs --static --dont-define-prefix hdr10plus_tool/BuildAction/lib/pkgconfig/hdr10plus-rs.pc)
        else
            set -g -a cflags -DLIBDOVI_FOUND=1 -DLIBHDR10PLUS_RS_FOUND=1 (pkg-config --cflags --static --dont-define-prefix dovi_tool/BuildAction/lib/x86_64-linux-gnu/pkgconfig/dovi.pc) (pkg-config --cflags --static --dont-define-prefix hdr10plus_tool/BuildAction/lib/x86_64-linux-gnu/pkgconfig/hdr10plus-rs.pc)
            set -g -a ldflags (pkg-config --libs --static --dont-define-prefix dovi_tool/BuildAction/lib/x86_64-linux-gnu/pkgconfig/dovi.pc) (pkg-config --libs --static --dont-define-prefix hdr10plus_tool/BuildAction/lib/x86_64-linux-gnu/pkgconfig/hdr10plus-rs.pc)
        end
    end

    # arch
    if test $arch = "X64"
        set -g -a cmake_command -DENABLE_AVX512=ON
    end
    set -g -a cflags $cflags_arch

    # LTO
    # if begin test $os = "macOS" ; and test $arch = "ARM64" ; end
    #     # [macOS arm64] For some reason manually specifying `-flto` is broken and doesn't link, so using `-DSVT_AV1_LTO=ON` for now.
    #     set -g -a cmake_command -DSVT_AV1_LTO=ON
    # else
        set -g -a cmake_command -DSVT_AV1_LTO=OFF
        if test $os != "Linux"
            set -g -a cflags -flto=full
            set -g -a ldflags -flto=full
        else
            # [Linux x86-64] `-flto=thin` should be faster than `-flto=full`.
            set -g -a cflags -flto=thin
            set -g -a ldflags -flto=thin
        end
        set -g -a cflags -fwhole-program-vtables
        set -g -a ldflags -fwhole-program-vtables
        if test $argv[2] = "final"
            set -g -a cflags -fvisibility=hidden -fvisibility-inlines-hidden
            set -g -a ldflags -fvisibility=hidden -fvisibility-inlines-hidden
        end
        if test $os != "Windows"
            set -g -a ldflags -Wl,--lto-O3
        end
    # end

    # PGO
    if test $argv[2] = "profiling"
        set -g -a cflags -fprofile-generate=PGO -ftemporal-profile
    else
        if test $os = "Windows"
            set -g -a cflags -fprofile-use=(cygpath -m -a PGO/default.profdata)
        else
            set -g -a cflags -fprofile-use=(realpath PGO/default.profdata)
        end
    end

    # user
    set -g -a cmake_command $flag_cmakeflags
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
function parameters_armv8.7_a_crypto_sm4_sha3_fp16_sve_sve2_oryon_1
    set -g cflags_arch -march=armv8.7-a+crypto+sm4+sha3+fp16+sve+sve2 -mtune=oryon-1
    parameters_base $argv[1] $argv[2]
end
function parameters_armv8.5_a_simd_crypto_apple_m3
    set -g cflags_arch -march=armv8.5-a+simd+crypto -mtune=apple-m3
    parameters_base $argv[1] $argv[2]
end
function parameters_skylake
    set -g cflags_arch -march=skylake -mtune=skylake -mno-gather 
    parameters_base $argv[1] $argv[2]
end

function build
    if test $arch = "X64"
        echo $cmake_command -DCMAKE_C_FLAGS_RELEASE="$cflags" -DCMAKE_CXX_FLAGS_RELEASE="$cflags" -DCMAKE_EXE_LINKER_FLAGS_RELEASE="$ldflags"
        $cmake_command -DCMAKE_C_FLAGS_RELEASE="$cflags" -DCMAKE_CXX_FLAGS_RELEASE="$cflags" -DCMAKE_EXE_LINKER_FLAGS_RELEASE="$ldflags"
    else
        echo CFLAGS="$cflags" CXXFLAGS="$cflags" LDFLAGS="$ldflags" $cmake_command
        CFLAGS="$cflags" CXXFLAGS="$cflags" LDFLAGS="$ldflags" $cmake_command
    end
    and ninja -v -C svt_build
    or return $status
end


# $argv[1]: directory string: "icelake-server+znver5", "znver2", "x86-64-v3+znver2"
function pgo_build
    set -g parameters parameters_(string replace --all - _ (string replace --all + _ $argv[1]))

    set prof_files PGO/*.profraw PGO/*.profdata
    rm -rf svt_build Build $prof_files
    or return $status
    find PGO -type f

    echo "[build-svt-av1] Profiling building $argv[1]"
    $parameters static profiling
    build
    or return $status

    echo "[build-svt-av1] Profiling $argv[1]"
    Bin/Release/SvtAv1EncApp -i PGO/PGO.y4m -b /dev/null --preset 2 $flag_pgo_parameters
    or return $status
    llvm-profdata merge -o PGO/default.profdata PGO/*.profraw
    or return $status
    find PGO -type f

    mkdir -p BuildAction/$argv[1]
    or return $status
    for static in "static" "shared"
        if test (eval echo \$flag_$static) != "false"
            rm -rf svt_build Build
            or return $status
    
            echo "[build-svt-av1] Final building $static $argv[1]"
            $parameters $static final
            build
            or return $status
    
            mv Bin/Release BuildAction/$argv[1]/$static
            or return $status
    
            echo "[build-svt-av1] Final $static $argv[1]"
            if test $os != "macOS"
                ldd BuildAction/$argv[1]/$static/SvtAv1EncApp
            else
                otool -L BuildAction/$argv[1]/$static/SvtAv1EncApp
            end
            BuildAction/$argv[1]/$static/SvtAv1EncApp --help | grep dolby
            or return $status
            BuildAction/$argv[1]/$static/SvtAv1EncApp --help | grep hdr10plus
            or return $status
            BuildAction/$argv[1]/$static/SvtAv1EncApp -i PGO/PGO.y4m -b /dev/null $flag_pgo_parameters --preset 4
            or return $status
    
            echo "[build-svt-av1] Result $static $argv[1]"
            find BuildAction/$argv[1]/$static -type f
        end
    end

    # [Linux x86-64] BOLT is currently having problems with fully static binaries, and making the binaries static outweigh the benefit of BOLT.
    # [Linux x86-64] In the future if BOLT can actually be used, this is the way you can perform BOLT on your own build.
    # [Linux x86-64] 1. Add `-Wl,--emit-relocs,-znow` to `LDFLAGS`.
    # [Linux x86-64] 2. Add these commands after build:
    # [Linux x86-64]    ```sh
    # [Linux x86-64]    perf record -e cycles:u -j any,u -o PGO/perf.data -- Bin/Release/SvtAv1EncApp -i PGO/PGO.y4m -b /dev/null --preset 2 --crf 20.00 --lineart-psy-bias 5 --texture-psy-bias 5
    # [Linux x86-64]    perf2bolt -p PGO/perf.data -o PGO/perf.fdata Bin/Release/SvtAv1EncApp
    # [Linux x86-64]    llvm-bolt Bin/Release/SvtAv1EncApp -o Bin/Release/SvtAv1EncApp.bolt -data=PGO/perf.fdata --relocs --remove-symtab --eliminate-unreachable --hugify --align-blocks --reorder-blocks=ext-tsp --reorder-functions-use-hot-size --use-edge-counts --min-branch-clusters --split-functions --split-strategy=profile2 --split-eh --split-all-cold --frame-opt=all --frame-opt-rm-stores --reg-reassign --use-aggr-reg-reassign --inline-memcpy --inline-ap --shorten-instructions --infer-fall-throughs --infer-stale-profile --equalize-bb-counts --iterative-guess --indirect-call-promotion=all --indirect-call-promotion-use-mispredicts --icp-eliminate-loads --jump-tables=aggressive --simplify-rodata-loads --plt=all --icf=1 --peepholes=all --eliminate-unreachable --elim-link-veneers --group-stubs --fix-block-counts --fix-func-counts --match-profile-with-function-hash --match-with-call-graph --use-compact-aligner --preserve-blocks-alignment --x86-align-branch-boundary-hot-only --x86-strip-redundant-address-size --tail-duplication=cache --simplify-conditional-tail-calls --sctc-mode=heuristic --dyno-stats --icp-mp-threshold=1
    # [Linux x86-64]    ```
end


if test $arch = "X64"
    if test $os = "macOS"
        pgo_build skylake
        or return $status
    else
        if test $flag_base_arch_only != "true"
            pgo_build icelake-server+znver5
            pgo_build znver2
        end
        pgo_build x86-64-v3+znver2
        or return $status
    end
else
    if test $os = "macOS"
        pgo_build armv8.5-a+simd+crypto+apple-m3
        or return $status
    else
        pgo_build armv8.7-a+crypto+sm4+sha3+fp16+sve+sve2+oryon-1
        or return $status
    end
end
