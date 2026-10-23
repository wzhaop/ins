#!/usr/bin/env bash

set -e

CMAKE_OSX_ARCHITECTURES="arm64e;arm64"
CMAKE_OSX_SYSROOT="iphoneos"

# Prerequisites
if [ -z "$(ls -A modules/FLEXing)" ]; then
    echo -e '\033[1m\033[0;31mFLEXing submodule not found.\nPlease run the following command to checkout submodules:\n\n\033[0m    git submodule update --init --recursive'
    exit 1
fi

# Building modes
if [ "$1" == "sideload" ];
then

    # Check if building with dev mode
    if [ "$2" == "--dev" ];
    then
        # Cache pre-built FLEX libs
        mkdir -p "packages/cache"
        cp -f ".theos/obj/debug/FLEXing.dylib" "packages/cache/FLEXing.dylib" 2>/dev/null || true
        cp -f ".theos/obj/debug/libflex.dylib" "packages/cache/libflex.dylib" 2>/dev/null || true

        if [[ ! -f "packages/cache/FLEXing.dylib" || ! -f "packages/cache/libflex.dylib" ]]; then
            echo -e '\033[1m\033[0;33mCould not find cached pre-built FLEX libs, building prerequisite binaries\033[0m'
            echo

            ./build.sh sideload --buildonly
            ./build-dev.sh true
            exit
        fi

        MAKEARGS='DEV=1'
        FLEXPATH=''
        COMPRESSION=0
    else
        # Clear cached FLEX 
        rm -rf "packages/cache"

        MAKEARGS='SIDELOAD=1'
        FLEXPATH=''
        COMPRESSION=9
    fi

    # Clean build artifacts
    make clean
    rm -rf .theos

    # Check for decrypted instagram ipa
    ipaFile="$(find ./packages/*com.burbn.instagram*.ipa -type f -exec basename {} \;)"
    if [ -z "${ipaFile}" ]; then
        echo -e '\033[1m\033[0;31m./packages/com.burbn.instagram.ipa not found.\nPlease put a decrypted Instagram IPA in its path.\033[0m'
        exit 1
    fi

    echo -e '\033[1m\033[32mBuilding SCInsta tweak for sideloading (as IPA)\033[0m'

    make $MAKEARGS

    # Only build libs (for future use in dev build mode)
    if [ "$2" == "--buildonly" ];
    then
        exit
    fi

    SCINSTAPATH=".theos/obj/debug/SCInsta.dylib"
    if [ "$2" == "--devquick" ];
    then
        # Exclude SCInsta.dylib from ipa for livecontainer quick builds
        SCINSTAPATH=""
    fi

    # Create IPA File
    echo -e '\033[1m\033[32mCreating the IPA file...\033[0m'

    # --- 新增：深度精简底包冗余文件 ---
    echo -e '\033[1m\033[33mCleaning up redundant files and patching Info.plist...\033[0m'
    unzip -q "packages/${ipaFile}" -d "packages/temp_extract"
    APP_DIR=$(find "packages/temp_extract/Payload" -type d -name "*.app" | head -n 1)
    
    # 1. 强力彻底删除所有扩展程序及文件夹 (解决 Bundle ID 不匹配报错)
    rm -rf "${APP_DIR}/PlugIns"
    rm -rf "${APP_DIR}/Extensions"
    find "${APP_DIR}" -type d -name "*.appex" -exec rm -rf {} +
    # 2. 删除 Apple Watch 应用
    rm -rf "${APP_DIR}/Watch"
    # 3. 删除多余语言包 (仅保留英文、简体中文和基础架构)
    find "${APP_DIR}" -type d -name "*.lproj" -not -name "en.lproj" -not -name "Base.lproj" -not -name "zh-Hans.lproj" -exec rm -rf {} +

    # 4. 修改 Info.plist，禁止应用在 iOS“文件”App 中生成文件夹
    PLIST_PATH="${APP_DIR}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :UIFileSharingEnabled false" "${PLIST_PATH}" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :UIFileSharingEnabled bool false" "${PLIST_PATH}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :LSSupportsOpeningDocumentsInPlace false" "${PLIST_PATH}" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :LSSupportsOpeningDocumentsInPlace bool false" "${PLIST_PATH}" 2>/dev/null || true
    
    # 重新打包成精简版底包，并清理临时文件
    cd "packages/temp_extract" && zip -qr "../cleaned_base.ipa" Payload && cd ../..
    rm -rf "packages/temp_extract"
    
    ipaFile="cleaned_base.ipa"
    # --- 精简结束 ---

    rm -f packages/SCInsta-sideloaded.ipa
    cyan -i "packages/${ipaFile}" -o packages/SCInsta-sideloaded.ipa -f $SCINSTAPATH $FLEXPATH -c $COMPRESSION -m 15.0 -du
    
    # Patch IPA for sideloading
    ipapatch --input "packages/SCInsta-sideloaded.ipa" --inplace --noconfirm

    # --- 新增：在最终生成的 IPA 中强制关闭文件共享，防止注入工具复原 ---
    echo -e '\033[1m\033[33mDisabling UIFileSharingEnabled in final IPA...\033[0m'
    unzip -q "packages/SCInsta-sideloaded.ipa" -d "packages/final_extract"
    FINAL_APP_DIR=$(find "packages/final_extract/Payload" -type d -name "*.app" | head -n 1)
    
    /usr/libexec/PlistBuddy -c "Set :UIFileSharingEnabled false" "${FINAL_APP_DIR}/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :LSSupportsOpeningDocumentsInPlace false" "${FINAL_APP_DIR}/Info.plist" 2>/dev/null || true
    
    cd "packages/final_extract" && rm -f "../SCInsta-sideloaded.ipa" && zip -qr "../SCInsta-sideloaded.ipa" Payload && cd ../..
    rm -rf "packages/final_extract"
    # --- 结束 ---

    echo -e "\033[1m\033[32mDone, we hope you enjoy SCInsta!\033[0m\n\nYou can find the ipa file at: $(pwd)/packages"

elif [ "$1" == "rootless" ];
then
    
    # Clean build artifacts
    make clean
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding SCInsta tweak for rootless\033[0m'

    export THEOS_PACKAGE_SCHEME=rootless
    make package

    echo -e "\033[1m\033[32mDone, we hope you enjoy SCInsta!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

elif [ "$1" == "rootful" ];
then

    # Clean build artifacts
    make clean
    rm -rf .theos

    echo -e '\033[1m\033[32mBuilding SCInsta tweak for rootful\033[0m'

    unset THEOS_PACKAGE_SCHEME
    make package

    echo -e "\033[1m\033[32mDone, we hope you enjoy SCInsta!\033[0m\n\nYou can find the deb file at: $(pwd)/packages"

else
    echo '+--------------------+'
    echo '|SCInsta Build Script|'
    echo '+--------------------+'
    echo
    echo 'Usage: ./build.sh <sideload/rootless/rootful>'
    exit 1
fi
