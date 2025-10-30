#!/bin/bash

# 环境检查和自动安装脚本

check_command() {
    command -v "$1" >/dev/null 2>&1
}

install_cmake() {
    log_info "安装 CMake..."
    
    if [[ "$OS_TYPE" == "macos" ]]; then
        if check_command brew; then
            brew install cmake
        else
            log_error "请先安装 Homebrew: https://brew.sh"
            exit 1
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if check_command apt-get; then
            sudo apt-get update
            sudo apt-get install -y cmake
        elif check_command yum; then
            sudo yum install -y cmake
        else
            log_error "无法自动安装 CMake，请手动安装"
            exit 1
        fi
    fi
}

download_android_ndk() {
    log_info "下载 Android NDK..."
    
    NDK_VERSION="r26c"
    NDK_DIR="$HOME/android-ndk-$NDK_VERSION"
    
    if [ -d "$NDK_DIR" ]; then
        log_success "Android NDK 已存在: $NDK_DIR"
        export ANDROID_NDK_ROOT="$NDK_DIR"
        return 0
    fi
    
    if [[ "$OS_TYPE" == "macos" ]]; then
        NDK_URL="https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-darwin.dmg"
        NDK_FILE="android-ndk-$NDK_VERSION-darwin.dmg"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        NDK_URL="https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip"
        NDK_FILE="android-ndk-$NDK_VERSION-linux.zip"
    else
        log_error "不支持的操作系统"
        return 1
    fi
    
    log_info "从 $NDK_URL 下载..."
    
    # 检查是否已下载
    if [ ! -f "/tmp/$NDK_FILE" ]; then
        curl -L -o "/tmp/$NDK_FILE" "$NDK_URL"
    fi
    
    # 解压
    if [[ "$OS_TYPE" == "macos" ]]; then
        hdiutil attach "/tmp/$NDK_FILE"
        cp -R "/Volumes/Android NDK $NDK_VERSION/AndroidNDK*.app/Contents/NDK" "$NDK_DIR"
        hdiutil detach "/Volumes/Android NDK $NDK_VERSION"
    else
        unzip -q "/tmp/$NDK_FILE" -d "$HOME"
    fi
    
    export ANDROID_NDK_ROOT="$NDK_DIR"
    log_success "Android NDK 安装完成: $NDK_DIR"
}

check_and_setup_environment() {
    local platforms="$1"
    
    log_info "检查构建环境..."
    
    # 检查 CMake
    if ! check_command cmake; then
        log_warning "未找到 CMake"
        read -p "是否自动安装 CMake? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_cmake
        else
            log_error "CMake 是必需的"
            exit 1
        fi
    else
        log_success "CMake 已安装: $(cmake --version | head -n 1)"
    fi
    
    # iOS 环境检查
    if [[ "$platforms" == *"ios"* ]] || [[ "$platforms" == *"all"* ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            if ! check_command xcodebuild; then
                log_error "未找到 Xcode，iOS 构建需要 Xcode"
                exit 1
            else
                log_success "Xcode 已安装: $(xcodebuild -version | head -n 1)"
            fi
        fi
    fi
    
    # Android 环境检查
    if [[ "$platforms" == *"android"* ]] || [[ "$platforms" == *"all"* ]]; then
        # 检查 NDK
        if [ -z "$ANDROID_NDK_ROOT" ] && [ -z "$NDK_ROOT" ]; then
            log_warning "未设置 ANDROID_NDK_ROOT 环境变量"
            
            # 尝试查找常见位置
            POSSIBLE_NDK_PATHS=(
                "$HOME/Library/Android/sdk/ndk"
                "$HOME/Android/Sdk/ndk"
                "/usr/local/android-ndk"
            )
            
            for path in "${POSSIBLE_NDK_PATHS[@]}"; do
                if [ -d "$path" ]; then
                    # 找到最新版本
                    NDK_VERSION=$(ls "$path" | sort -V | tail -n 1)
                    if [ -n "$NDK_VERSION" ]; then
                        export ANDROID_NDK_ROOT="$path/$NDK_VERSION"
                        log_success "找到 Android NDK: $ANDROID_NDK_ROOT"
                        break
                    fi
                fi
            done
            
            if [ -z "$ANDROID_NDK_ROOT" ]; then
                log_warning "未找到 Android NDK"
                read -p "是否自动下载 Android NDK? (y/n) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    download_android_ndk
                else
                    log_error "Android 构建需要 NDK"
                    exit 1
                fi
            fi
        else
            log_success "Android NDK: ${ANDROID_NDK_ROOT:-$NDK_ROOT}"
        fi
        
        # 检查 Java（用于编译 JAR）
        if ! check_command javac; then
            log_warning "未找到 Java，JAR 编译可能失败"
        else
            log_success "Java 已安装: $(javac -version 2>&1)"
        fi
    fi
    
    # 鸿蒙环境检查
    if [[ "$platforms" == *"harmony"* ]] || [[ "$platforms" == *"all"* ]]; then
        if [ -z "$OHOS_NDK_ROOT" ]; then
            log_warning "未设置 OHOS_NDK_ROOT，跳过鸿蒙构建"
            log_info "请从 HarmonyOS SDK 获取 NDK 并设置环境变量"
        else
            log_success "HarmonyOS NDK: $OHOS_NDK_ROOT"
        fi
    fi
    
    log_success "环境检查完成"
}

