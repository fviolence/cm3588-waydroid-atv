# Android patch inventory and design notes

This project builds LineageOS 23.2 / Android 16 TV for the FriendlyElec CM3588 Plus under Waydroid.

## Patch order and validation

Two independent patch layers are required:

1. **Upstream Waydroid:** `vendor/extra/waydroid-patches/base-patches-36/` contains **51** patches in the tested manifest. Apply with `bash vendor/extra/waydroid-patches/apply-patches.sh` from the Android source root. This establishes the `autopatch/base-patches-36` tag in `bionic`.
2. **CM3588 adaptations:** this repository's `patches/` directory contains **28 patches** across **15 Android Git repositories**. Apply using `scripts/apply-cm3588-patches.sh` after the upstream stage.

The CM3588 installer checks for the upstream `bionic` tag, expects unmodified HWC at commit `ce61fbc895d183279c304c1d1c516a710d587c7f`, and checks that every target checkout exists and is clean before application. If a patch fails, it attempts to abort `git am` in the failing repository, then stops; previously applied repositories are **not** automatically rolled back. Do not blindly rerun an installer against a partially patched tree.

## CM3588 patch inventory

| Android project | Patches | Purpose |
| --- | ---: | --- |
| `hardware/waydroid` | 11 | Bifrost DMA-BUF HWC path, Android 16 display/HIDL compatibility, gralloc allocation probe, and avoidance of incompatible legacy modules |
| `device/lineage/sepolicy` | 1 | Restrict GmsCore `apk_verity` access according to board API level |
| `device/waydroid/waydroid` | 1 | CM3588 Mali initialization and optional legacy HAL integration |
| `external/XMP-Toolkit-SDK` | 2 | Permit vendor variants of XMP Toolkit and `zuid_md5` |
| `external/ffmpeg` | 1 | Enable the ARM64 NEON MPEGVideo initializer |
| `external/google-highway` | 1 | Permit the vendor variant of `libhwy` |
| `external/minigbm` | 1 | Skip Mesa GBM wrapper without a Mesa backend |
| `external/skia` | 1 | Permit the vendor variant of `libskia_skcms` |
| `external/stagefright-plugins` | 2 | Codec2 planar YUV420P conversion and disabling the FFmpeg AV1 decoder registration |
| `frameworks/base` | 1 | Disable Cobalt low-end mode for YouTube TV 7.27.302 using a guarded bootstrap setting |
| `frameworks/native` | 1 | Request linear framebuffer targets for Mali in SurfaceFlinger |
| `packages/apps/TvSettings` | 1 | Fall back to current mode for virtual display settings |
| `system/core` | 2 | Container cgroup-root handling and software-sync LLNDK exports |
| `vendor/extra` | 1 | CM3588-specific Waydroid service configuration selection |
| `vendor/waydroid/init` | 1 | Detection of the proprietary CM3588 Mali graphics stack |
| **Total** | **28** | **15 target projects** |

## Important constraints

- **HWC base is exact:** do not move the upstream HWC revision forward or apply this series to an arbitrary Waydroid checkout. The 11-patch series was validated against the pinned original commit.
- **No automatic rollback across repositories:** in case of a failed patch, inspect the affected Git history and worktree before continuing; do not reset or resync the entire checkout without diagnosis.
- **Mali binaries are external:** `vendor/cm3588/proprietary/` is intentionally ignored. Build definitions alone do not provide working hardware graphics libraries. Redistribution requires appropriate rights.
- **YouTube TV:** the framework patch is limited to `com.google.android.youtube.tv` on `cm3588_atv` and checks the bootstrap file format before setting `DisableLowEndDeviceMode`. Review it for other app versions.
- **Graphics and device integration are not production-certified:** linear buffer assumptions, host device-node permissions, SELinux policy interactions and SurfaceFlinger behavior should be validated on each supported kernel/Waydroid combination.

## Graphics and display

- **Mali g29p0:** Bifrost allocator/mapper and `arm.graphics-V5-ndk` use graphics-common V4. A non-installed compatibility prebuilt avoids the Soong V4/V7 dependency conflict; the installed vendor V4 is Android-generated.
- **Allocator service:** declare `android.hardware.graphics.common@1.2` and `libcutils` in `shared_libs` to satisfy ELF dependency checks.
- **HWC:** SurfaceFlinger requests linear framebuffer targets; the Waydroid HWC validates DMA-BUF layouts before import.
- **Remote OK/Select:** HWC tracks `KEY_CNT` Linux keys without truncating keycodes, allowing `KEY_SELECT` (353) to reach Android as `DPAD_CENTER`. `KEY_ENTER` instead dismisses the on-screen keyboard. The [CEC bridge](https://github.com/fviolence/cm3588-cec-remote) supplies the input event.
- **Host rendering:** Weston uses the Rockchip VOP2 forced-composition workaround documented in the [host runtime repository](https://github.com/fviolence/cm3588-waydroid-host). This is not an Android source patch.
