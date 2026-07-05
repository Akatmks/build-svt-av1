## Akatmks/build-svt-av1@v1

This is a GitHub Action to build SVT-AV1 for Windows x86-64, Windows arm64, Linux x86-64, macOS arm64, and macOS x86-64.  
By utilising the best compiler and best procedure, including LTO and PGO, this building script can create highly optimised builds within 1% of the best possible build.  

SVT-AV1 variants and build repositories using this action:  
* [5fish/SVT-AV1](https://github.com/5fish/SVT-AV1)  

SVT-AV1 variants and build repositories that is currently in the process of implementing this action:  
* SVT-AV1-HDR  
* SVT-AV1-Tritium  

### Usage

Please check the GitHub Workflow in the various linked repositories above to see how this action is used.  

This action will install clang, nasm, rust, as well as ffmpeg, MSYS2, and other components all on its own.  
If you want to link the static lib built by this action into other projects, you can use the same clang this action leaves to build it, but do check the code for how or which clang to use.  

Please read through this entire Usage section including the maintainence information at the end.  

#### Reference  

```yml
- uses: Akatmks/build-svt-av1@v1
  with:
    # Path to SVT-AV1 repository.
    # Ideally the absolute path to the repository should not contain any spaces or any characters that will confuse POSIX shell.
    # This directory will be littered after use.
    # Default: "."
    path: "."

    # Whether to build static app and lib.
    # Default: "true"
    static: "true"

    # Whether to build shared app and lib.
    # Set static and shared both to "false" results in nothing being output.
    # Default: "false"
    shared: "false"

    # Currently we perform PGO using either a clip of SolLevante or a clip of FoodMarket2.
    # Use "SolLevante" if this build will more likely be used to encode 2D content such as anime or some genre of games.
    # Use "FoodMarket2" if this build will more likely be used to encode liveaction and 3D content.
    # You can also set this to "false" and put your own PGO clip in `PGO/PGO.y4m` in the SVT-AV1 repository. 
    # Default: "SolLevante"
    pgo-video: "SolLevante"

    # We currently provide multiple builds for different generations of x86-64 systems.
    # Set this to true to only build `x86-64-v3+znver2` version.
    # Default: "false"
    base-arch-only: "false"

    # Build dovi and hdr10plus into the app.
    # Default: "true"
    dovi-hdr10plus: "true"

    # Build FFMS2 into the app.
    # Sorry We don't support it yet.
    ffms2: "false"

    # Additional cmake parameters for building.
    # As an example, you can add `-DUSE_WEBM_IO=ON` when building SVT-AV1-Essential.
    # Default: ""
    cmakeflags: ""

    # Additional CFLAGS, CXXFLAGS, LDFLAGS for profiling and final build.
    # Please escape all quotation marks using backslashes `\`.
    # Default: ""
    cflags-profiling: ""
    cxxflags-profiling: ""
    ldflags-profiling: ""
    cflags-final: ""
    cxxflags-final: ""
    ldflags-final: ""
```

#### Results  

The resulting builds will be available in the following directory within the SVT-AV1 repository.  
```
BuildAction/[ARCH]/[STATIC]/[FILENAME]
```
* `[ARCH]`:
  * On Windows x86-64 and Linux x86-64, `icelake-server+znver5`, `znver2`, or `x86-64-v3+znver2`. Both `icelake-server+znver5` and `znver2` version can be missing depending on the specific GitHub Action runner.  
  * On Windows arm64, `armv8.7-a+crypto+sm4+sha3+fp16+sve+sve2+oryon-1`.  
  * On macOS arm64, `armv8.5-a+simd+crypto+apple-m3`.  
  * On macOS x86-64, `skylake`.  
* `[STATIC]`: `static` or `shared`.  
* `[FILENAME]`:
  * For the app, it would be `SvtAv1EncApp.exe` on Windows, and `SvtAv1EncApp` on Unix.  
  * For the lib, it would the respective native filename for the system, such as `libSvtAv1Enc.a`, `libSvtAv1EncApp.so`, `libSvtAv1EncApp.VERSION.so`. You can directly `-L` to the directory.  

#### Maintainence

A new main version (such as `Akatmks/build-svt-av1@v1` ⇒ `Akatmks/build-svt-av1@v2`) will be released when:  
* We change the `-march` and `-mtune` in any of the builds, either due to new clang version having different preference, or due to GitHub Actions server upgrading to a different hardware.  
  When you're updating, make sure you update the output binary path as explained [above](#results).  
* We change the compiler used in any of the builds, such as changing from `clang` & `clang++` to `clang-cl`, or changing from LLVM project clang to Intel/LLVM.  
  This doesn't affect people using the app, but for people using the static lib, make sure things are still working.  

#### Note

This is not a requirement, but when you're using this action to build anything, we kindly ask you to include this message when distributing your builds.  
```
Thanks to studies and contributions from afed, Emre, Ironclad, Itachi Uchiha, Khaoklong, Miss Ashenlight, Soda, SwareJonge, Trix, Yiss, and other people in the community for discovering the method to build the fastest binary.
```
You may rephrase the sentence if needed.  
You can also add additional names, including your own, to the list. The list is currently sorted in alphabetical order.  

### Contribution

If you can optimise this building process in any way, such as optimising compiling parameters and change optimisation processes, feel free to raise a discussion in the AV1 related servers, or open a pull request here.  
