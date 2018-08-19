#!/bin/bash

set -e

################################################################

PATCHLEVEL=4073
ENABLE_ASSERT=ON
BUILD_LLGO=OFF
BUILD_LLDB=OFF

# less used llvm tools
LLVM_UNCOMMON_TOOLS=OFF
LLVM_YAML_OBJECT_TOOLS=OFF
LLVM_MINIMAL_FAST_BUILD=OFF
# regular clang tools
CLANG_TOOLS=OFF
# stuff that depends on extra and extra tools themselves
CLANG_TOOLS_EXTRA=OFF
# arcmt and analyzer
CLANG_ANALYZER_AND_ARCMT=OFF

################################################################
# best kept off
CLANG_USELESS_TOOLS=OFF
LLVM_USELESS_TOOLS=OFF
BUILD_FUZZERS=OFF
# gophers
GOLLVM_DISABLE_LIBGO=ON
GOLLVM_BUILD=OFF
################################################################
# sdk used for building this
SDKROOT=/usr/local/sdk/llvm-8.0.4070
################################################################
# this shouldn't be changed too often
SRC_ROOT=/q/SourceCache/llvm-trunk-8.0
TOOLCHAIN_VERS="8.0.$PATCHLEVEL"
################################################################
# okay rest of the script is guts 
################################################################

# crutch to use ad-hoc sdks
# export LD_LIBRARY_PATH=$SDKROOT/lib

if [[ $1 = "gs" ]]; then
  echo "-------------------------------------"
  echo "Git status for LLVM:"
  echo "-------------------------------------"
  git status
  echo "-------------------------------------"
  echo "Git status for Clang:"
  echo "-------------------------------------"
  cd tools/clang
  git status
  exit 0
fi

if [[ $1 = "gcl" ]]; then
  echo "-------------------------------------"
  echo "Clang autocommit"
  echo "-------------------------------------"
  cd tools/clang
  echo "--- Adding lib/ and inclide/ ..."
  git add -v lib/
  git add -v include/
  git utccommit -m "[tools/clang]: autocommit of lib/ and include/"
  echo "--- Adding clang tools CMakeLists.txt ..."
  git add tools/CMakeLists.txt
  git utccommit -m "[tools/clang/tools]: autocommit of tools cmakelists"
  echo "--- Adding clang tools/extra CMakeLists.txt ..."
  cd tools/extra/
  git add CMakeLists.txt
  git utccommit -m "[tools/clang/tools/extra]: autocommit of tools cmakelists"
  echo "--- Committing to local ..."
  
  exit 0
fi

if [[ $1 = "pull" ]]; then
  export GIT_MERGE_AUTOEDIT=no
  
  echo "-------------------------------------"
  echo "Updating LLVM Core ..."
  echo "-------------------------------------"
  echo ""
  
  git pull 

  echo ""
  echo "-------------------------------------"
  echo "Updating projects ..."
  echo "------------------------------------"
  
  
  cd projects
  echo -e "\n ------------- compiler-rt -------------"
  git -C compiler-rt pull
  echo -e " ------------- libc++ -------------"
  git -C libcxx pull
  echo -e " ------------- libcxxabi -------------"
  git -C libcxxabi pull
  echo -e " ------------- libunwind -------------"
  git -C libunwind pull

  echo ""
  echo "-------------------------------------"
  echo "Updating tools ..."
  echo "-------------------------------------"
  cd ../tools
  
  echo -e "\n ------------- Clang -------------"
  git -C clang pull
  echo -e "------------- LLD -------------"
  git -C lld pull
  echo -e "------------- Polly -------------"
  git -C polly pull
  echo -e "------------- LLDB -------------"
  git -C lldb pull
  echo -e "------------- GOLLVM -------------"
  git -C gollvm pull
  echo -e "------------- LLGO (SVN) -------------"
  svn update llgo
  echo -e "------------- Clang Extra -------------"
  cd clang/tools/extra
  git pull

  # tools -> clang -> tools -> (LLVM ROOT)
  cd ../../..

  echo -e "Checkout done!"
  echo ""
  echo " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo " !!!!!!! DONT FORGET TO INCREASE PATCHLEVEL !!!!!!!"
  echo " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo " !!!!!!! CURRENT: $PATCHLEVEL"
  echo " !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  echo " - Have a pleasant build!"
  echo " - Use './llvm.sh go' to start."
  echo ""
  exit 0
fi

NIGHTLY_SYMLINK="nightly"
LLVM_VERSION_SUFFIX="svn"
ASSERTS_NOTICE=""

LTO_TYPE=Thin
LTO_LINKOPT="-Wl,-lto-O2"

if [[ $ENABLE_ASSERT = "ON" ]]; then
#  LLVM_VERSION_SUFFIX="svn_assert"
#  NIGHTLY_SYMLINK="nightly_asserts"
  ASSERTS_NOTICE=" - Assertions Enabled Build"
#  TOOLCHAIN_VERS="8.0.$PATCHLEVEL"
fi

if [[ $LLVM_MINIMAL_FAST_BUILD == "ON" ]]; then
  LTO_TYPE=OFF
  BUILD_LLGO=OFF
  BUILD_LLDB=OFF
  LLVM_UNCOMMON_TOOLS=OFF
  LLVM_YAML_OBJECT_TOOLS=OFF
  CLANG_TOOLS=OFF
  CLANG_TOOLS_EXTRA=OFF
  CLANG_ANALYZER_AND_ARCMT=OFF
  CLANG_USELESS_TOOLS=OFF
  LLVM_USELESS_TOOLS=OFF
  BUILD_FUZZERS=OFF
  USE_ALT_NIGHTLY_SYMLINK=ON
  LTO_LINKOPT=""
  NIGHTLY_SYMLINK="minimal_static_nightly"
  echo "--- LLVM_MINIMAL_FAST_BUILD is enabled, switched off most options."
fi

if [[ $CLANG_ANALYZER_AND_ARCMT != "ON" ]]; then
  CLANG_USELESS_TOOLS="OFF"
  CLANG_TOOLS_EXTRA="OFF"
fi

if [[ $CLANG_TOOLS_EXTRA != "ON" ]]; then
  CLANG_USELESS_TOOLS="OFF"
fi

BASE_BUILD_ROOT=/o/org.llvm.caches/llvm-8.0/$PATCHLEVEL
BUILD_ROOT=$BASE_BUILD_ROOT
THINLTO_CACHE=$BUILD_ROOT/thinlto.cache.useless
INSTALL_PATH=/usr/local/sdk/llvm-$TOOLCHAIN_VERS

mkdir -p $BUILD_ROOT
cd $BUILD_ROOT
echo "--- Entered directory: $BUILD_ROOT"

BINPATH=$SDKROOT/bin

export GOPATH=/usr/lib/go-1.6/bin
export CXX=$BINPATH/clang++
export CC=$BINPATH/clang
export AS=$BINPATH/clang

# !!!!!!!!!!!!!!!!!!!! ACHTUNG! !!!!!!!!!!!!!!!!!!!!!!!!
#
# DO NOT SHIP LIBCXX OR LIBCXXABI OR LIBCOMPILER_RT 
# IN THIS VARIATION. SERVERS *DO NOT* SUPPORT IT AND 
# IT CAUSES THE PROCESSOR TO BEHAVE ODDLY.
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
ALL_FLAGS="-march=skylake -rtlib=compiler-rt"

LINKER_FLAGS="-fuse-ld=$BINPATH/ld.lld $ALL_FLAGS -L$SRC_ROOT/kristinas_sysroot/lib -L$SDKROOT/lib ${LTO_LINKOPT}"

export PATH="$BINPATH:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "--- Updated PATH: $PATH"

if [[ $1 = "purge" ]]; then
  rm -rf ${BUILD_ROOT}
  echo -e "--- Purged build root: ${BUILD_ROOT}"
  exit 0
fi

if [[ $1 = "install" ]]; then
  echo " ************* STARTING INSTALL **************** "
  echo " * To:   $INSTALL_PATH "
  echo " * From: $PWD"
   
  read -p " * Are you sure? Press Y to continue or anything else to abort." -n 1 -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    echo -ne "\n * Aborted per user request!\n"
    exit 1
  fi
  
  echo -ne "\n ************* INSTALLING TO ${INSTALL_PATH} **************** \n"
  
  sudo cmake -DCMAKE_INSTALL_PREFIX="$INSTALL_PATH" -P cmake_install.cmake
  
  STAMP_HEADER=$INSTALL_PATH/include/c++/v1/__libcpp_nightly_stamp.h
  
  sudo rm -f $STAMP_HEADER
  sudo touch $STAMP_HEADER
  sudo chmod 666 $STAMP_HEADER
  echo -ne "#pragma once\n#define LIBCPP_NIGHTLY_PATCHLEVEL ${PATCHLEVEL}\n" > $STAMP_HEADER
  
  echo "--- Symlinking to $NIGHTLY_SYMLINK ..."
  
  cd /usr/local/sdk/ 
  sudo rm -f $NIGHTLY_SYMLINK
  sudo ln -s "llvm-$TOOLCHAIN_VERS" $NIGHTLY_SYMLINK
  
  echo "--- Merging in libunwind headers ..." 
  
  sudo cp -r $SRC_ROOT/projects/libunwind/include $INSTALL_PATH/include/c++/v1/unwind
  sudo mv $INSTALL_PATH/include/c++/v1/unwind/__libunwind_config.h $INSTALL_PATH/include/c++/v1/__libunwind_config.h
  
  echo "--- Writing build stamp ..."
  
  sudo rm -f $INSTALL_PATH/.build_stamp
  sudo touch $INSTALL_PATH/.build_stamp
  sudo chmod 666 $INSTALL_PATH/.build_stamp
  echo "$PATCHLEVEL" > $INSTALL_PATH/.build_stamp
  
  echo "--- Writing SDK metadata file ..."
  
  sudo rm -f $INSTALL_PATH/.sdk_info.json
  sudo touch $INSTALL_PATH/.sdk_info.json
  sudo chmod 666 $INSTALL_PATH/.sdk_info.json
  echo "{\"ver\":[8,0,$PATCHLEVEL],\"used_sdk\":\"$SDKROOT\",\"install\":\"$INSTALL_PATH\",\"cache\":\"$BUILD_ROOT\",\"assert\":\"$ENABLE_ASSERT\"}" > $INSTALL_PATH/.sdk_info.json
  
  exit 0
fi

CLANG_BINARY=$BUILD_ROOT/bin/clang-8

if [[ $1 = "readelf" ]]; then
  echo " ************* READELF $CLANG_BINARY **************** "
  readelf -d $CLANG_BINARY
  exit 0
fi

if [[ $1 = "ldd" ]]; then
  echo " ************* LDD $CLANG_BINARY **************** "
  ldd $CLANG_BINARY
  exit 0
fi

if [[ $1 = "tldd" ]]; then
  echo " ************* TLDD $CLANG_BINARY **************** "
  tldd $CLANG_BINARY
  exit 0
fi

cd $BUILD_ROOT

LLVM_BINDINGS=""

if [[ $BUILD_LLGO == "ON" ]]; then
  echo "--- BUILD_LLGO is enabled, setting GOPATH and enabling Go bindings."
  GO_EXECUTABLE=$GOPATH/go
  LLVM_BINDINGS="go;${LLVM_BINDINGS}"
else
  GO_EXECUTABLE=OFF
fi

if [[ $GOLLVM_BUILD != "ON" ]]; then
  GOLLVM_DISABLE_LIBGO=OFF
fi

print_toplevel_conf() {
  echo "--------------------------------------------------------------"
  echo "LLVM Configuration:"
  echo "--------------------------------------------------------------"
  echo "LIBLLVM:                   $TOOLCHAIN_VERS$LLVM_VERSION_SUFFIX"
  echo "BUILD_LLDB:                $BUILD_LLDB"
  echo "BUILD_FUZZERS:             $BUILD_FUZZERS"
  echo "LLVM_BINDINGS:             $LLVM_BINDINGS"
  echo "LLVM_YAML_OBJECT_TOOLS:    $LLVM_YAML_OBJECT_TOOLS"
  echo "LLVM_UNCOMMON_TOOLS:       $LLVM_UNCOMMON_TOOLS"
  echo "LLVM_USELESS_TOOLS:        $LLVM_USELESS_TOOLS"
  echo "LLVM_MINIMAL_FAST_BUILD:   $LLVM_MINIMAL_FAST_BUILD (Disables LTO and most tools)"
  echo "--------------------------------------------------------------"
  echo "Global Configuration:"
  echo "--------------------------------------------------------------"
  echo "ENABLE_ASSERT:             $ENABLE_ASSERT"
  echo "LTO_TYPE:                  $LTO_TYPE"
  echo "LTO_LINKOPT:               $LTO_LINKOPT"
  echo "--------------------------------------------------------------"
  echo "Clang Configuration:"
  echo "--------------------------------------------------------------"
  echo "CLANG_ANALYZER_AND_ARCMT:  $CLANG_ANALYZER_AND_ARCMT (Required by most tools)"
  echo "CLANG_TOOLS_EXTRA:         $CLANG_TOOLS_EXTRA (Required by libclang)"
  echo "CLANG_USELESS_TOOLS:       $CLANG_USELESS_TOOLS (Depend on extra)"
  echo "CLANG_TOOLS:               $CLANG_TOOLS"
  echo "--------------------------------------------------------------"
  echo "LLGO Configuration:"
  echo "--------------------------------------------------------------"
  echo "BUILD_LLGO:                $BUILD_LLGO (If on, will also enable bindings)"
  echo "GOPATH:                    $GOPATH (Host go toolchain to build llgo)"
  echo "--------------------------------------------------------------"
  echo "LLVM Go Configuration:"
  echo "--------------------------------------------------------------"
  echo "GOLLVM_BUILD:              $GOLLVM_BUILD"
  echo "GOLLVM_DISABLE_LIBGO:      $GOLLVM_DISABLE_LIBGO (Depends on gollvm)"
  echo "--------------------------------------------------------------"
  echo "Roots:"
  echo "--------------------------------------------------------------"
  echo "SRC_ROOT:     $SRC_ROOT"
  echo "BUILD_ROOT:   $BUILD_ROOT"
  echo "INSTALL_PATH: $INSTALL_PATH"
  echo "SDKROOT:      $SDKROOT"
  echo "--------------------------------------------------------------"
}

if [[ $1 = "dry" ]]; then
  echo -e " ************* DRY RUN FOR ${TOOLCHAIN_VERS}${ASSERTS_NOTICE} **************** "
  print_toplevel_conf
  exit 0
fi

if [[ $1 = "build" ]]; then
  echo -e " ************* STARTING BUILD ONLY FOR ${TOOLCHAIN_VERS}${ASSERTS_NOTICE} **************** "
  print_toplevel_conf
  cmake --build .
  exit 0
fi

if [[ $1 != "go" ]]; then
  print_toplevel_conf
  echo "Nothing to do, no command specified!"
  echo "Call this with './llvm.sh go' to actually start the build"
  echo "Use './llvm.sh build' to build without reconfiguring cmake"
  exit 1
fi


echo -e " ************* STARTING CMAKE+BUILD FOR ${TOOLCHAIN_VERS}${ASSERTS_NOTICE} **************** "

print_toplevel_conf

cmake $SRC_ROOT -GNinja \
  -DLLVM_BINDINGS=$LLVM_BINDINGS \
  -DBUILD_SHARED_LIBS=OFF \
  -DDISABLE_LIBGO_BUILD=$GOLLVM_DISABLE_LIBGO \
  -DGO_EXECUTABLE=$GO_EXECUTABLE \
  -DPACKAGE_VENDOR="LLVM/Kristina${ASSERTS_NOTICE} (org.llvm.${TOOLCHAIN_VERS}):\\n " \
  -DLLVM_VERSION_PATCH=$PATCHLEVEL \
  -DLLVM_VERSION_SUFFIX=$LLVM_VERSION_SUFFIX \
  -DLLVM_TOOL_OBJ2YAML_BUILD=$LLVM_YAML_OBJECT_TOOLS \
  -DLLVM_TOOL_YAML2OBJ_BUILD=$LLVM_YAML_OBJECT_TOOLS \
  -DLLVM_TOOL_LLGO_BUILD=$BUILD_LLGO \
  -DLLVM_TOOL_LLDB_BUILD=$BUILD_LLDB \
  -DLLVM_TOOL_BUGPOINT_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_BUGPOINT_PASSES_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_GOLD_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_LLVM_CFI_VERIFY_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_LLVM_COV_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_LLVM_CXXFILT_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_LLVM_CXXDUMP_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_LLVM_C_TEST_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_LLVM_MCA_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_LLVM_MC_ASSEMBLE_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_LLVM_MC_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_LLVM_PDBUTIL_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_LLVM_PROFDATA_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_LLVM_GOC_BUILD=$GOLLVM_BUILD \
  -DLLVM_TOOL_LLVM_EXEGESIS_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_LLVM_OPT_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_LLVM_ISEL_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_LLVM_SPECIAL_CASE_LIST_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_LLVM_MC_DISASSEMBLE_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_LLVM_DEMANGLE_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_LLVM_AS_FUZZER_BUILD=$BUILD_FUZZERS \
  -DLLVM_TOOL_GOLLVM_BUILD=$GOLLVM_BUILD \
  -DLLVM_TOOL_LLI_BUILD=$LLVM_UNCOMMON_TOOLS \
  -DLLVM_TOOL_SANCOV_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_SANSTATS_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_XCODE_TOOLCHAIN_BUILD=$LLVM_USELESS_TOOLS \
  -DLLVM_TOOL_CLANG_TOOLS_EXTRA_BUILD=$CLANG_TOOLS_EXTRA \
  -DLLVM_TARGETS_TO_BUILD="Native;X86" \
  -DLLVM_POLLY_LINK_INTO_TOOLS=ON \
  -DLLVM_LIBXML2_ENABLED=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_MODULES=ON \
  -DLLVM_ENABLE_LTO=$LTO_TYPE \
  -DLLVM_ENABLE_LLD=ON \
  -DLLVM_INCLUDE_UTILS=ON \
  -DLLVM_ENABLE_ASSERTIONS=$ENABLE_ASSERT \
  -DLLVM_ENABLE_ABI_BREAKING_CHECKS=OFF \
  -DLLVM_LINK_LLVM_DYLIB=ON \
  -DLLVM_PARALLEL_LINK_JOBS=4 \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLIBXML2_LIBRARIES=IGNORE \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBUNWIND_USE_COMPILER_RT=ON \
  -DLIBUNWIND_INSTALL_LIBRARY=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_ENABLE_FILESYSTEM=ON \
  -DLIBCXX_CXX_ABI="default" \
  -DLIBCXX_ABI_UNSTABLE=1 \
  -DLIBCXX_USE_COMPILER_RT=ON \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXXABI_INSTALL_LIBRARY=OFF \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
  -DLIBCXXABI_ENABLE_ASSERTIONS=ON \
  -DLIBCXXABI_USE_COMPILER_RT=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_LIBFUZZER=$BUILD_FUZZERS \
  -DCOMPILER_RT_BUILD_BUILTINS=ON \
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
  -DCMAKE_SHARED_LINKER_FLAGS="$LINKER_FLAGS" \
  -DCMAKE_RANLIB=$BINPATH/llvm-ranlib \
  -DCMAKE_OBJDUMP=$BINPATH/llvm-objdump \
  -DCMAKE_OBJCOPY=$BINPATH/llvm-objcopy \
  -DCMAKE_OBJCOPY=$BINPATH/llvm-nm \
  -DCMAKE_MODULE_LINKER_FLAGS="$LINKER_FLAGS" \
  -DCMAKE_LINKER=$BINPATH/ld.lld \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PATH \
  -DCMAKE_EXE_LINKER_FLAGS="$LINKER_FLAGS" \
  -DCMAKE_CXX_FLAGS="-O3 $ALL_FLAGS -Wno-unused-command-line-argument" \
  -DCMAKE_CXX_COMPILER=$BINPATH/clang++ \
  -DCMAKE_C_COMPILER=$BINPATH/clang \
  -DCMAKE_C_FLAGS="-O3 -march=skylake" \
  -DCMAKE_BUILD_TYPE=RELEASE \
  -DCMAKE_ASM_COMPILER=$BINPATH/clang \
  -DCMAKE_AR=$BINPATH/llvm-ar \
  -DCMAKE_FIND_ROOT_PATH="$SRC_ROOT/kristinas_sysroot" \
  -DCLANG_TOOL_ARCMT_TEST_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_CLANG_CHECK_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_CLANG_DIFF_BUILD=$CLANG_TOOLS \
  -DCLANG_TOOL_CLANG_FORMAT_BUILD=$CLANG_ANALYZER_AND_ARCMT \
  -DCLANG_TOOL_CLANG_FORMAT_VS_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_CLANG_FUNC_MAPPING_BUILD=$CLANG_TOOLS \
  -DCLANG_TOOL_CLANG_FUZZER_BUILD=$BUILD_FUZZERS \
  -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_CLANG_OFFLOAD_BUNDLER_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_CLANG_REFACTOR_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_CLANG_RENAME_BUILD=$CLANG_TOOLS \
  -DCLANG_TOOL_C_ARCMT_TEST_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_C_INDEX_TEST_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_DIAGTOOL_BUILD=$CLANG_TOOLS \
  -DCLANG_TOOL_LIBCLANG_BUILD=$CLANG_TOOLS_EXTRA \
  -DCLANG_TOOL_SCAN_BUILD_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_SCAN_VIEW_BUILD=$CLANG_USELESS_TOOLS \
  -DCLANG_TOOL_EXTRA_BUILD=$CLANG_TOOLS_EXTRA \
  -DCLANG_VERSION_PATCHLEVEL=$PATCHLEVEL \
  -DCLANG_VENDOR_UTI="org.llvm.clang-kb.$TOOLCHAIN_VERS" \
  -DCLANG_VENDOR="Kristina's toolchain (${TOOLCHAIN_VERS}${ASSERTS_NOTICE}) " \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_DEFAULT_LINKER="lld" \
  -DCLANG_DEFAULT_OBJCOPY="llvm-objcopy" \
  -DCLANG_ENABLE_ARCMT=$CLANG_ANALYZER_AND_ARCMT \
  -DCLANG_DEFAULT_CXX_STDLIB="libc++" \
  -DCLANG_DEFAULT_RTLIB="compiler-rt" \
  -DCLANG_ENABLE_STATIC_ANALYZER=$CLANG_ANALYZER_AND_ARCMT \
  -DSANITIZER_CXX_ABI="libc++" \
  -DSANITIZER_CXX_ABI_INTREE=ON

echo -e " ************* STARTING BUILD FOR ${TOOLCHAIN_VERS}${ASSERTS_NOTICE} **************** "

print_toplevel_conf

cmake --build .

tldd "$CLANG_BINARY"

