#!/bin/sh
# Copyright (C) Marvin Scholz

# Include vlc env script
source "$(dirname "$0")/../macosx/env.build.sh" "none"

#
# Global variables
#

# Variables for things that need
# to be changed from time to time:

VLC_DEPLOYMENT_TARGET_MACOSX="10.10"
VLC_DEPLOYMENT_TARGET_IOS="9.0"
VLC_DEPLOYMENT_TARGET_TVOS="11.0"

# Name of this script
VLC_SCRIPT_NAME=$(basename "$0")
# Dir of this script
VLC_SCRIPT_DIR=$(dirname "$0")
# VLC source dir root
VLC_SRC_DIR=$(vlcGetRootDir)
# VLC build dir
VLC_BUILD_DIR=$(pwd)
# Whether verbose output is enabled or not
VLC_SCRIPT_VERBOSE=0
# Architecture of the host (OS that the result will run on)
VLC_HOST_ARCH=x86_64
# Host platform information
VLC_HOST_PLATFORM=
VLC_HOST_TRIPLET=
VLC_HOST_PLATFORM_SIMULATOR=
VLC_HOST_OS=
# Lowest OS version (iOS, tvOS or macOS) to target
VLC_DEPLOYMENT_TARGET=
# Flags for linker and compiler that set the min target OS
VLC_DEPLOYMENT_TARGET_LDFLAG=
VLC_DEPLOYMENT_TARGET_CFLAG=
# SDK name (optionally with version) to build with
VLC_APPLE_SDK_NAME="macosx"
# SDK path
VLC_APPLE_SDK_PATH=
# SDK version
VLC_APPLE_SDK_VERSION=

# Prints command line usage
usage()
{
    echo "Usage: $VLC_SCRIPT_NAME [--arch=ARCH]"
    echo " --arch=ARCH    architecture to build for"
    echo "                  (all|i386|x86_64|armv7|armv7s|arm64)"
    echo " --sdk=SDK      name of the SDK to build with (see 'xcodebuild -showsdks')"
    echo " --help         print this help"
}

# Print error message and terminate script execution
abort_err()
{
    echo >&2 "ERROR: $1"
    exit 1
}

# Print message if verbose, else silent
verbose_msg()
{
    if [ "$VLC_SCRIPT_VERBOSE" -gt "0" ]; then
        echo "$1"
    fi
}

# Check if tool exists, if not error out
check_tool()
{
    command -v "$1" >/dev/null 2>&1 || {
        abort_err "This script requires '$1' but it was not found"
    }
}

# Check failure of the last run command
check_failure()
{
    if [ ! $? -eq 0 ]; then
        abort_err "$1"
    fi
}

# Set the VLC_DEPLOYMENT_TARGET* flag options correctly
set_deployment_target()
{
    VLC_DEPLOYMENT_TARGET="$1"
    VLC_DEPLOYMENT_TARGET_LDFLAG="-Wl,-$VLC_HOST_OS"
    VLC_DEPLOYMENT_TARGET_CFLAG=-$VLC_HOST_OS

    if [ -n "$VLC_HOST_PLATFORM_SIMULATOR" ]; then
        VLC_DEPLOYMENT_TARGET_LDFLAG+="_simulator"
        VLC_DEPLOYMENT_TARGET_CFLAG+="-simulator"
    fi

    VLC_DEPLOYMENT_TARGET_LDFLAG+="_version_min,$VLC_DEPLOYMENT_TARGET"
    VLC_DEPLOYMENT_TARGET_CFLAG+="-version-min=$VLC_DEPLOYMENT_TARGET"
}

# Take SDK name, verify it exists and populate
# VLC_HOST_*, VLC_APPLE_SDK_PATH and VLC_DEPLOYMENT_TARGET
# variables based on the SDK
validate_sdk_name()
{
    xcrun --sdk "$VLC_APPLE_SDK_NAME" --show-sdk-path >/dev/null 2>&1 || {
        abort_err "Failed to find SDK '$1'"
    }

    VLC_APPLE_SDK_PATH="$(xcrun --sdk "$VLC_APPLE_SDK_NAME" --show-sdk-path)"
    VLC_APPLE_SDK_VERSION="$(xcrun --sdk "$VLC_APPLE_SDK_NAME" --show-sdk-version)"
    if [ ! -d "$VLC_APPLE_SDK_PATH" ]; then
        abort_err "SDK at '$VLC_APPLE_SDK_PATH' does not exist"
    fi

    case "$1" in
        iphoneos*)
            VLC_HOST_PLATFORM="iOS"
            VLC_HOST_OS="iOS"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_IOS"
            ;;
        iphonesimulator*)
            VLC_HOST_PLATFORM="iOS-Simulator"
            VLC_HOST_PLATFORM_SIMULATOR="yes"
            VLC_HOST_OS="ios"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_IOS"
            ;;
        appletvos*)
            VLC_HOST_PLATFORM="tvOS"
            VLC_HOST_OS="tvos"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_TVOS"
            ;;
        appletvsimulator*)
            VLC_HOST_PLATFORM="tvOS-Simulator"
            VLC_HOST_PLATFORM_SIMULATOR="yes"
            VLC_HOST_OS="tvos"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_TVOS"
            ;;
        macosx*)
            VLC_HOST_PLATFORM="macOS"
            VLC_HOST_OS="macosx"
            set_deployment_target "$VLC_DEPLOYMENT_TARGET_MACOSX"
            ;;
        watch*)
            abort_err "Building for watchOS is not supported by this script"
            ;;
        *)
            abort_err "Unhandled SDK name '$1'"
            ;;
    esac

    verbose_msg "Using $VLC_HOST_PLATFORM $VLC_APPLE_SDK_VERSION SDK ($VLC_APPLE_SDK_PATH)"
}

# Parse arguments
while [ -n "$1" ]
do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --verbose)
            VLC_SCRIPT_VERBOSE=1
            ;;
        --arch=*)
            VLC_HOST_ARCH="${1#--arch=}"
            ;;
        --sdk=*)
            VLC_APPLE_SDK_NAME="${1#--sdk=}"
            ;;
        *)
            echo >&2 "ERROR: Unrecognized option '$1'"
            usage
            exit 1
            ;;
    esac
    shift
done

# Check for some required tools before proceeding
check_tool xcrun
check_tool xcodebuild

# Validate given SDK name
validate_sdk_name "$VLC_APPLE_SDK_NAME"

# Set SDKROOT variable, used by various Apple tools and
# the symbol env script in VLC
export SDKROOT="$VLC_APPLE_SDK_PATH"

# Set triplet (query the compiler for this)
VLC_HOST_TRIPLET="$(${CC:-cc} -arch "$VLC_HOST_ARCH" -dumpmachine)"

# Set pseudo-triplet #FIXME:
VLC_PSEUDO_TRIPLET=$VLC_HOST_ARCH-apple-$VLC_HOST_PLATFORM_$VLC_DEPLOYMENT_TARGET

echo "Build configuration:"
echo "  Platform:     $VLC_HOST_PLATFORM"
echo "  Architecture: $VLC_HOST_ARCH"
echo "  SDK Version:  $VLC_APPLE_SDK_VERSION"
echo ""

#
# Extras tools build
#

echo "Building needed tools (if missing)"

cd "$VLC_SRC_DIR/extras/tools"

./bootstrap
check_failure "Bootstrapping tools failed"

make
check_failure "Building tools failed"

echo ""

#
# Env variables for the build
#

CPPFLAGS=

CFLAGS="$VLC_DEPLOYMENT_TARGET_CFLAG -arch "$VLC_HOST_ARCH""
OBJCFLAGS="$VLC_DEPLOYMENT_TARGET_CFLAG -arch "$VLC_HOST_ARCH""
CXXFLAGS="$VLC_DEPLOYMENT_TARGET_CFLAG -arch "$VLC_HOST_ARCH""

LDFLAGS="$VLC_DEPLOYMENT_TARGET_LDFLAG"

#
# Contrib build
#

echo "Building contribs for $VLC_HOST_ARCH"

# Create dir to build contribs in
cd "$VLC_SRC_DIR/contrib"
mkdir -p "contrib-$VLC_PSEUDO_TRIPLET"
cd "contrib-$VLC_PSEUDO_TRIPLET"

# Set symbol blacklist for autoconf
vlcSetSymbolEnvironment > /dev/null

# Create contrib install dir if it does not already exist
VLC_CONTRIB_INSTALL_DIR="$VLC_BUILD_DIR/contrib/$VLC_PSEUDO_TRIPLET"
mkdir -p "$VLC_CONTRIB_INSTALL_DIR"

# Bootstrap contribs
../bootstrap --host="$VLC_HOST_TRIPLET" --prefix="$VLC_CONTRIB_INSTALL_DIR"
check_failure "Bootstrapping contribs failed"

# Build contribs
make
check_failure "Building contribs failed"
