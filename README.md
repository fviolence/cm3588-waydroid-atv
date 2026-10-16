# CM3588 Waydroid Android TV

LineageOS 23.2 / Android 16 TV for the [FriendlyElec CM3588 Plus](https://wiki.friendlyelec.com/wiki/index.php/CM3588) (Rockchip RK3588), running inside [Waydroid](https://waydro.id/) on a Linux host with proprietary Mali/Bifrost graphics and a patched Waydroid hardware composer.

**Status:** Android TV runs at 4K60 with YouTube playback.

[CM3588 WayDroid host installation](https://github.com/fviolence/cm3588-waydroid-host) describes the Debian runtime, Weston, WayDroid initialization and unattended TV startup. Remote control input is provided by the separate [HDMI-CEC bridge](https://github.com/fviolence/cm3588-cec-remote).

## Host requirements

WayDroid requires a compatible RK3588 Linux kernel with Binder/BinderFS, namespaces, cgroups, DRM/Mali, and network support. See the [host installation guide](https://github.com/fviolence/cm3588-waydroid-host#installation) for runtime checks and the [kernel backports repository](https://github.com/fviolence/cm3588-kernel-security-backports) for kernel configuration and build instructions.

## Repository contents

| Location | Purpose |
| --- | --- |
| [`manifest/default.xml`](manifest/default.xml) | Android/LineageOS source manifest |
| [`manifest/cm3588.xml`](manifest/cm3588.xml) | Pinned CM3588 device/vendor and upstream Waydroid HWC projects |
| [`patches/`](patches/) | 28 CM3588 Git patches, organized by Android source path |
| [`scripts/apply-cm3588-patches.sh`](scripts/apply-cm3588-patches.sh) | Preflight checks and CM3588 patch application |
| [`docs/patches.md`](docs/patches.md) | Patch inventory, sequencing, rationale and limitations |

The device and vendor source definitions are published separately as [android_device_cm3588_atv](https://github.com/fviolence/android_device_cm3588_atv) and [android_vendor_cm3588](https://github.com/fviolence/android_vendor_cm3588). The HWC starts from a pinned revision of [waydroid/android_hardware_waydroid](https://github.com/waydroid/android_hardware_waydroid), then receives the patches in this repository.

> Proprietary Mali driver binaries are not included, see section [2.1. Proprietary Mali-G610 graphics libraries](#21-proprietary-mali-g610-graphics-libraries)

## 1. Prepare a Linux build host

Plan for **at least 350 GB of free working storage**.

### Arch Linux

Install the build dependencies from Arch's official repositories:

```bash
sudo pacman -Syu --needed \
  base-devel git git-lfs repo ccache python curl rsync \
  bc bison flex gperf gnupg \
  zip unzip zstd lz4 lzop \
  libxml2 libxslt ncurses zlib openssl \
  squashfs-tools pngcrush imagemagick \
  fontconfig ttf-dejavu e2fsprogs android-tools
```

For additional background, see the [ArchWiki Android build guide](https://wiki.archlinux.org/title/Android).

### Ubuntu 24.04 LTS and newer

The Android `repo` package is provided by Ubuntu's official **`multiverse`** repository. Some other dependencies, including `pngcrush`, are provided by **`universe`**.

Enable both components if they are not already enabled:

```bash
sudo apt update
sudo apt install -y software-properties-common

sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse
```

Install the build dependencies:

```bash
sudo apt update

sudo apt install -y \
  build-essential git git-lfs repo ccache \
  python3 python-is-python3 curl rsync \
  bc bison flex gperf gnupg ca-certificates \
  zip unzip zstd lz4 lzop \
  libxml2-dev libxml2-utils libxslt1-dev xsltproc \
  libncurses-dev zlib1g-dev libssl-dev \
  libelf-dev libdw-dev \
  squashfs-tools pngcrush imagemagick \
  fontconfig fonts-dejavu-core e2fsprogs
```

### Debian 12 (Bookworm) / Debian 13 (Trixie)

The Android `repo` package is available from Debian's official **`contrib`** repository component.

Ensure that `contrib` is enabled in your existing APT sources before installing dependencies.

For installations using the modern Deb822 configuration (typically `/etc/apt/sources.list.d/debian.sources`), add `contrib` to the existing `Components:` entries, for example:

```text
Components: main contrib
```

For installations using traditional `/etc/apt/sources.list` entries, include `contrib` after `main`, retaining the existing distribution codename and repository URLs.

Install the build dependencies:

```bash
sudo apt update

sudo apt install -y \
  build-essential git git-lfs repo ccache \
  python3 python-is-python3 curl rsync \
  bc bison flex gperf gnupg ca-certificates \
  zip unzip zstd lz4 lzop \
  libxml2-dev libxml2-utils libxslt1-dev xsltproc \
  libncurses-dev zlib1g-dev libssl-dev \
  libelf-dev libdw-dev \
  squashfs-tools pngcrush imagemagick \
  fontconfig fonts-dejavu-core e2fsprogs
```

**Architecture note:** This project builds an ARM64-only Android userspace (`TARGET_ARCH=arm64`), with no secondary 32-bit Android architecture (`TARGET_2ND_ARCH` is empty).

## 2. Configure workspace paths and build options

```bash
export WORK_ROOT="$HOME/android-work"                 # Root directory; allow approximately 350 GB
export PROJECT_NAME="cm3588-waydroid-atv"             # This repository
export SOURCE_NAME="cm3588-atv-platform"              # Android source checkout

# Adjust to your hardware
export SYNC_JOBS=8
export BUILD_JOBS=8
export CCACHE_SIZE="30G"

export PROJECT_DIR="$WORK_ROOT/$PROJECT_NAME"
export ANDROID_DIR="$WORK_ROOT/$SOURCE_NAME"
export CCACHE_DIR="$WORK_ROOT/.ccache"
export MALI_ARCHIVE="$WORK_ROOT/mali-blobs.tar.gz"
```

Create the workspace and check available storage:

```bash
mkdir -p "$WORK_ROOT"
df -h "$WORK_ROOT"
```

All examples below assume a **fresh Android source checkout**. Never run the two patch installers again on an already patched tree.

### 2.1. Proprietary Mali-G610 graphics libraries

Obtain the [official FriendlyELEC firmware](https://wiki.friendlyelec.com/wiki/index.php/CM3588#Install_OS) from an authorized source:

- Firmware filename (tested donor): `rk3588-eflasher-androidtv-20251222.img.gz`.
- SHA-256 (compressed firmware): `d3ca70952e48a2f25be8321e1c142811ba77c0fdf2b0df986f46dba28d61992f`.
- In the eFlasher image, partition 1 contains `androidtv/super.img`; logical partition `vendor_a` contains the proprietary libraries.

The critical official GLES binary is `libGLES_mali.so`, SHA-256 `0abeb1f8fe66f95bb9e41fdf0c5e41846b72445ebf59701cf3169706903314c0`.

### 2.2. Required proprietary payload

`MALI_ARCHIVE` is a user-created archive whose root is `proprietary/`. For the g29p0 configuration it contains **eight** files:

```text
proprietary/
├── bin/hw/android.hardware.graphics.allocator-V1-service
├── etc/init/android.hardware.graphics.allocator-V1-service.rc
├── etc/vintf/manifest/manifest_allocator.xml
└── lib64/
    ├── arm.graphics-V5-ndk.so
    ├── egl/libGLES_mali.so
    └── hw/
        ├── android.hardware.graphics.allocator-V1-arm.so
        ├── android.hardware.graphics.allocator-V1-bifrost.so
        └── android.hardware.graphics.mapper@4.0-impl-bifrost.so
```

### 2.3. Extract official `vendor_a` and package the libraries

The extraction requires `simg2img` and `lpunpack` in `PATH` (both are provided by `android-tools`).

```bash
export OFFICIAL_ATV_GZ=/path/to/rk3588-eflasher-androidtv.img.gz
export EXTRACT_DIR="$WORK_ROOT/friendlyelec-atv14"
```

```bash
mkdir -p "$EXTRACT_DIR"/{eflasher,vendor,partitions,payload/proprietary}
printf '%s  %s\n' \
  d3ca70952e48a2f25be8321e1c142811ba77c0fdf2b0df986f46dba28d61992f \
  "$OFFICIAL_ATV_GZ" | sha256sum --check

gzip -dkc "$OFFICIAL_ATV_GZ" > "$EXTRACT_DIR/eflasher.img"
LOOP=$(sudo losetup -rPf --show "$EXTRACT_DIR/eflasher.img")
printf 'Loop device: %s\n' "$LOOP"

sudo mount -o ro "${LOOP}p1" "$EXTRACT_DIR/eflasher"
simg2img "$EXTRACT_DIR/eflasher/androidtv/super.img" "$EXTRACT_DIR/super.raw.img"
lpunpack -p vendor_a "$EXTRACT_DIR/super.raw.img" "$EXTRACT_DIR/partitions"
sudo mount -t ext4 -o loop,ro,noload "$EXTRACT_DIR/partitions/vendor_a.img" "$EXTRACT_DIR/vendor"
```

Copy **only** the six official ELF files while the vendor partition is mounted.

```bash
for file in \
  bin/hw/android.hardware.graphics.allocator-V1-service \
  lib64/arm.graphics-V5-ndk.so \
  lib64/egl/libGLES_mali.so \
  lib64/hw/android.hardware.graphics.allocator-V1-arm.so \
  lib64/hw/android.hardware.graphics.allocator-V1-bifrost.so \
  lib64/hw/android.hardware.graphics.mapper@4.0-impl-bifrost.so
do
  mkdir -p "$EXTRACT_DIR/payload/proprietary/$(dirname "$file")"
  sudo cp -L "$EXTRACT_DIR/vendor/$file" "$EXTRACT_DIR/payload/proprietary/$file"
  sudo chown "$(id -u):$(id -g)" "$EXTRACT_DIR/payload/proprietary/$file"
done

mkdir -p "$EXTRACT_DIR/payload/proprietary/etc/init" \
         "$EXTRACT_DIR/payload/proprietary/etc/vintf/manifest"
cat > "$EXTRACT_DIR/payload/proprietary/etc/init/android.hardware.graphics.allocator-V1-service.rc" <<'RC'
service vendor.gralloc-v1 /vendor/bin/hw/android.hardware.graphics.allocator-V1-service
    class hal animation
    user system
    group graphics drmrpc
    capabilities SYS_NICE
RC

cp "$EXTRACT_DIR/vendor/etc/vintf/manifest/manifest_allocator.xml" \
  "$EXTRACT_DIR/payload/proprietary/etc/vintf/manifest/manifest_allocator.xml"
sha256sum "$EXTRACT_DIR/payload/proprietary/lib64/egl/libGLES_mali.so"
find "$EXTRACT_DIR/payload/proprietary" -type f | sort
```

The GLES checksum must match section 2.1, and the file count must be exactly eight. Unmount before cleaning up the loop device, then create the archive:

```bash
sudo umount "$EXTRACT_DIR/vendor"
sudo umount "$EXTRACT_DIR/eflasher"
sudo losetup -d "$LOOP"

test "$(find "$EXTRACT_DIR/payload/proprietary" -type f | wc -l)" -eq 8
tar -czf "$MALI_ARCHIVE" -C "$EXTRACT_DIR/payload" proprietary
```

## 3. Clone the project and fetch Android sources

```bash
git clone https://github.com/fviolence/cm3588-waydroid-atv.git "$PROJECT_DIR"
mkdir -p "$ANDROID_DIR"
cd "$ANDROID_DIR"
repo init -u https://github.com/fviolence/cm3588-waydroid-atv.git \
  -b master -m manifest/default.xml --git-lfs
```

Fetch the sources:

```bash
repo sync -c -j"$SYNC_JOBS" --no-tags    # This will take time and space
repo list -a -p | wc -l
repo status
```

The successfully tested manifest enumerated **1,186 projects**. A fresh checkout is expected to have a clean `repo status`.

Check the original upstream Waydroid HWC base:

```bash
git -C "$ANDROID_DIR/hardware/waydroid" rev-parse HEAD
```

The tested manifest resolves it to `ce61fbc895d183279c304c1d1c516a710d587c7f`.

## 4. Apply the upstream and CM3588 patch series

**Order matters:** upstream Waydroid Android 16 patches first, CM3588 patches second. The project-specific preflight deliberately rejects an unexpected HWC revision, missing checkouts, or dirty patch-target working trees. See [patch details](docs/patches.md).

```bash
cd "$ANDROID_DIR"
bash vendor/extra/waydroid-patches/apply-patches.sh
```

The pinned `base-patches-36` directory contains **51 patches**. The upstream script should report that all patches applied successfully. Check that its `bionic` tag was created:

```bash
git -C "$ANDROID_DIR/bionic" tag -l 'autopatch/base-patches-36'
```

Then apply the **28 project-specific patches across 15 repositories**:

```bash
"$PROJECT_DIR/scripts/apply-cm3588-patches.sh" "$ANDROID_DIR"
```

The installer should print `Preflight passed` and finish with `CM3588 patches applied successfully.` Confirm the patched HWC tree:

```bash
git -C "$ANDROID_DIR/hardware/waydroid" rev-parse 'HEAD^{tree}'
```

Expected for the tested patch series: `cbcb47513784353ba5875b53ecebd07e9b60d96c`.

## 5. Supply the private Mali/Bifrost payload

The build definitions exist in `vendor/cm3588`, but the proprietary driver binaries are intentionally **not tracked** in the public source repositories.

```bash
tar -xzf "$MALI_ARCHIVE" -C "$ANDROID_DIR/vendor/cm3588"
find "$ANDROID_DIR/vendor/cm3588/proprietary" -type f | sort
```

The g29p0 payload contains **eight files**. Its structure includes the Mali EGL implementation, Bifrost mapper and allocator libraries, allocator configuration, and supporting files.

```bash
git -C "$ANDROID_DIR/vendor/cm3588" status --short
```

> The vendor repository should remain clean because it ignores `proprietary/`.

The g29p0 build also requires an Android-generated `android.hardware.graphics.common-V4-ndk.so` at `proprietary/lib64/` as a **build-time-only** compatibility prebuilt; the installed V4 library comes from the Android source build.

Check that the pinned vendor build definitions actually select the g29p0 modules before building:

```bash
VENDOR_BP="$ANDROID_DIR/vendor/cm3588/Android.bp"
grep -En 'name:[[:space:]]*"(arm.graphics-V5-ndk|cm3588_graphics_common_v4_compat)"' "$VENDOR_BP"
```

Both module definitions must be present.

## 6. Build `system.img` and `vendor.img`

The successful configuration is **`lineage_cm3588_atv-trunk_staging-userdebug`**.

```bash
cd "$ANDROID_DIR"
export USE_CCACHE=1
mkdir -p "$CCACHE_DIR"
ccache -M "$CCACHE_SIZE"
source build/envsetup.sh
lunch lineage_cm3588_atv-trunk_staging-userdebug
```

Confirm the build environment:

```bash
get_build_var TARGET_PRODUCT
get_build_var TARGET_BUILD_VARIANT
get_build_var PRODUCT_OUT
```

Expected product: `lineage_cm3588_atv`; variant: `userdebug`.

The `cm3588_graphics_common_v4_compat` prebuilt in `vendor/cm3588/Android.bp` references an ELF that is generated by the Android source build. Temporarily create an **empty placeholder** at that exact, Git-ignored path, build the source module, then replace the placeholder with the verified real ELF.

### 6.1. Create the placeholder (once)

```bash
V4_INPUT="$ANDROID_DIR/vendor/cm3588/proprietary/lib64/android.hardware.graphics.common-V4-ndk.so"
test ! -e "$V4_INPUT" && test ! -L "$V4_INPUT" && touch "$V4_INPUT"
```

### 6.2. Build only the Android-generated V4 library

```bash
m -j"$BUILD_JOBS" android.hardware.graphics.common-V4-ndk
```

### 6.5. Verify the generated ELF

```bash
OUT="$(get_build_var PRODUCT_OUT)"
V4="$OUT/system/lib64/android.hardware.graphics.common-V4-ndk.so"
test -s "$V4"
readelf -d "$V4" | grep SONAME
```

### 6.4. Replace the placeholder and verify it

```bash
install -m 0644 "$V4" "$V4_INPUT"
test -s "$V4_INPUT"
readelf -d "$V4_INPUT" | grep -F '(SONAME)' | grep -F 'android.hardware.graphics.common-V4-ndk.so'
test -f "$V4_INPUT" && test ! -s "$V4_INPUT" && rm -- "$V4_INPUT"
```

### 6.5. Full build

```bash
m -j"$BUILD_JOBS" systemimage vendorimage
```

## 7. Validate the generated images

```bash
OUT="$(get_build_var PRODUCT_OUT)"
ls -lh "$OUT/system.img" "$OUT/vendor.img"
file "$OUT/system.img" "$OUT/vendor.img"
```

The images are **raw ext4 filesystems** (approximately 2.0 GiB system and 214 MiB vendor):

```bash
e2fsck -fn "$OUT/system.img" && e2fsck -fn "$OUT/vendor.img"
dumpe2fs -h "$OUT/vendor.img" 2>/dev/null | grep -E 'Filesystem state:|Filesystem features:|Block size:'
```

Check critical graphics files inside the built vendor image and capture portable checksums:

```bash
debugfs -R 'stat /lib64/hw/hwcomposer.waydroid.so' "$OUT/vendor.img"
debugfs -R 'stat /lib64/egl/libGLES_mali.so' "$OUT/vendor.img"
(cd "$OUT" && sha256sum system.img vendor.img) | tee "$WORK_ROOT/SHA256SUMS"
```

The vendor image should contain the Waydroid hardware composer, Mali GLES libraries, Bifrost graphics allocator/mapper, and CM3588 init rules.

## Verified scope and limitations

- **Build and runtime:** source-built Android 16 system/vendor images pass filesystem checks, boot with Mali g29p0, display 4K60, and play YouTube TV. Long-term stability and full hardware compatibility remain unverified.
- **CI:** the GitHub Actions workflow is a **source/patch smoke test**; it does not compile full images or perform hardware-in-the-loop boot tests.
- **YouTube TV:** the `frameworks/base` patch sets `DisableLowEndDeviceMode` in the guarded YouTube TV 7.27.302 bootstrap configuration to prevent Cobalt tile-memory exhaustion. Recheck compatibility after app updates.
- **Host rendering:** the companion [host installation repository](https://github.com/fviolence/cm3588-waydroid-host) documents the Weston 4K60 configuration and required Rockchip VOP2 renderer workaround.
- **Device identity:** the tested Android 16 build may advertise a Google TV/Sabrina compatibility fingerprint that refers to Android 12. Do not interpret this fingerprint as the actual Android platform version.
- **Proprietary drivers:** graphics binaries are user-supplied and are excluded from the public repository and release artifacts.

For explanations of the individual patch groups, see [`docs/patches.md`](docs/patches.md).
