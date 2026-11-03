# Architectural Blueprint: Implementing iOS Support in the Neper Toolchain

This document specifies how to extend the **Neper** direct-emitting toolchain to produce iOS applications (AArch64) with no Xcode project, no Swift or Objective-C compiler and no LLVM.

iOS builds on the Mach-O and Metal work already done for macOS (Mach-O emission, the Cocoa shell, `msl.e`). The ISA is the same. The differences are policy rather than machinery: mandatory code signing, no raw syscalls, no JIT, an app-bundle layout, and a UIKit lifecycle reached entirely through the Objective-C runtime. The hard problems are the signature, the toolchain-identity checks that the App Store applies, and the fact that nothing can be run on the Windows host.

Verify every constant against the current SDK headers and Apple's documentation. Treat everything marked **verify** as unconfirmed.

---

## 1. Compiler Backend

| Target | Platform value | Where it runs |
| :--- | :--- | :--- |
| `aarch64-ios` | `PLATFORM_IOS` (2) | Devices |
| `aarch64-ios-simulator` | `PLATFORM_IOSSIMULATOR` (7) | Simulator on Apple Silicon Macs only |

*   The AArch64 emitter and the Apple AArch64 ABI from the macOS target are reused. Apple's variant differs from AAPCS64 in the ways the macOS target already handles: `x18` reserved, variadic arguments passed on the stack, and 16 KiB pages.
*   `arm64e` is not required for third-party apps. Emit plain `arm64`.
*   **Hardware floating-point aggregates.** `CGRect` is a homogeneous float aggregate (four doubles), returned in `d0`-`d3`. Confirm that the C-ABI aggregate classification from the struct-by-value work covers this case before building UI on it (**verify**).

---

## 2. Binary Format: Mach-O for iOS

The macOS Mach-O writer is the base. Changes:

| Load command / field | iOS requirement |
| :--- | :--- |
| `LC_BUILD_VERSION` | `platform = 2`, `minos`, `sdk` set. This replaces the macOS values and drives dyld's policy and App Store validation. |
| `LC_MAIN` | Entry is `main`, which calls `UIApplicationMain`. |
| `LC_DYLD_CHAINED_FIXUPS`, `LC_DYLD_EXPORTS_TRIE` | The macOS writer already emits these. iOS 15 and later expect chained fixups. |
| `LC_LOAD_DYLIB` | By install name only: `/usr/lib/libSystem.B.dylib`, `/usr/lib/libobjc.A.dylib`, `/System/Library/Frameworks/UIKit.framework/UIKit`, and so on. |
| `LC_CODE_SIGNATURE` | **Required.** See section 3. |
| `LC_UUID`, `LC_SOURCE_VERSION` | As on macOS. |

*   System frameworks do not exist as files on a device. They live in the dyld shared cache, so linking by install name is the only possibility, and no `.tbd` stubs are needed by Neper because the importer writes install names directly.
*   Segment alignment is 16 KiB, as on Apple Silicon macOS.

---

## 3. Code Signing (the keystone)

An unsigned or invalidly signed Mach-O does not run on a device. The kernel validates every code page hash at fault time.

*   The signature is an embedded **SuperBlob** (`0xfade0cc0`) at `LC_CODE_SIGNATURE`, containing a **CodeDirectory** (`0xfade0c02`), requirements, and a CMS blob when signed with a real identity.
*   The CodeDirectory holds SHA-256 hashes of every 16 KiB page of the file up to the signature, plus special slots (`Info.plist`, requirements, `CodeResources`, entitlements).
*   Three signing levels, in order of build:
    1. **Ad-hoc** (no certificate, flags `0x2`). Runs in the Simulator and on jailbroken or developer-mode-exempt setups. Fully computable by Neper: SHA-256 plus a fixed struct layout.
    2. **Development** identity, with an `embedded.mobileprovision` that lists the device UDID. Needs an Apple Developer account and a certificate the user exports. The CMS signature uses the certificate's private key with RSA or ECDSA and SHA-256.
    3. **Distribution** identity for TestFlight and the App Store.
*   The user supplies certificate, key and profile. Neper never holds Apple credentials in the repository.
*   Existing cross-platform signers (`rcodesign`, `zsign`) are the reference to diff against, since a one-bit error produces only "code signature invalid" at launch. Build the writer first, then check it with `codesign -dvvv --verify` on a Mac.
*   Entitlements (`application-identifier`, `get-task-allow`, `com.apple.developer.team-identifier`) are an XML plist embedded in a signature slot and must match the provisioning profile exactly.

---

## 4. System Interface

*   **No raw syscalls.** Apple does not support the syscall ABI, and syscall numbers change. Everything goes through `libSystem` imports, as on macOS. Threads use `pthread_create`. `e.thread` calls the import, never `bsdthread_create`.
*   **No JIT and no writable-executable memory** without a special entitlement that App Store apps do not receive. Neper emits ahead-of-time code, so the base target is unaffected. Comptime evaluation (`neper eval`) runs on the build host only.
*   **Sandbox.** Each app sees only its container. `e.fs` paths are `NSHomeDirectory()`-relative (Documents, Library, tmp), reached through `NSSearchPathForDirectoriesInDomains` or `NSFileManager` over the runtime. No `fork`, no `execve`: `e.proc` is unavailable and must return a normal `err`.
*   **Memory.** The jetsam daemon kills the process on memory-footprint limits, with no swap. Arena reservations that cost only address space are fine. Committed pages are what count. Release arenas in `applicationDidReceiveMemoryWarning`.

---

## 5. UIKit Through the Objective-C Runtime

There is no Objective-C compiler, so UIKit is driven the way the macOS Cocoa shell drives AppKit.

| Need | Mechanism |
| :--- | :--- |
| Send a message | `objc_msgSend` imported from `libobjc.A.dylib`, **called through a prototype that matches each call exactly**. On arm64 Apple, variadic and non-variadic calls pass arguments differently, so one generic variadic extern is wrong. |
| Struct returns | No `objc_msgSend_stret` on arm64. `CGRect`/`CGPoint` return in registers by the C ABI. |
| Selectors, classes | `sel_registerName`, `objc_getClass`. Cache both at startup. |
| Define `AppDelegate` and a view subclass | `objc_allocateClassPair`, `class_addMethod` with an `@cc` function pointer, `objc_registerClassPair`. Method implementations are C-ABI Neper functions taking `(self, _cmd, ...)`. |
| Metal-backed view | A `UIView` subclass overriding `+layerClass` to return `CAMetalLayer`. |
| Entry | `UIApplicationMain(argc, argv, nil, @"AppDelegate")`, with the string created by `NSString` at runtime. |
| Scene lifecycle | Recent SDKs require the `UIScene` lifecycle (`UIApplicationSceneManifest` in `Info.plist`, a `UIWindowSceneDelegate` class) (**verify** the minimum SDK that enforces it). |
| Frame pacing | `CADisplayLink` with a target and selector. |
| Touch | A view subclass overriding `touchesBegan:/Moved:/Ended:/Cancelled:withEvent:`. |
| Keyboard | The view adopts `UIKeyInput` (`hasText`, `insertText:`, `deleteBackward`) and returns `YES` from `canBecomeFirstResponder`. |
| Accessibility | `UIAccessibility` properties on the view, or `accessibilityElements`, built the way the macOS `NSAccessibility` bridge is. |
| Block arguments | `dispatch_async` and many UIKit APIs want blocks. A block literal is a small struct (`isa`, `flags`, `invoke`, `descriptor`) built by hand with `_NSConcreteGlobalBlock`. |

*   Graphics are **Metal only**. OpenGL ES is deprecated and `--gpu glsl` is out. The existing Metal backend (`msl.e`) and the macOS Metal host calls carry over, with `CAMetalLayer` instead of `NSView` hosting.
*   `e.ui` presents into the `CAMetalLayer` drawable. The system supplies safe-area insets, scale factor (`contentScaleFactor`) and orientation. Layout code must read them, not assume a fixed display.

---

## 6. Packaging: The Neper IPA Pipeline (`neper ipa`)

| Step | Output |
| :--- | :--- |
| 1. Compile | Signed-ready Mach-O `MyApp` (section 2) |
| 2. Bundle | `MyApp.app/` containing the executable, `Info.plist`, assets, `embedded.mobileprovision` (development and distribution builds) |
| 3. `Info.plist` | `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`, `MinimumOSVersion`, `UIDeviceFamily`, `UIRequiredDeviceCapabilities` (`arm64`), `UILaunchScreen` (dictionary form, no storyboard needed), `UIApplicationSceneManifest`. XML plist is accepted. |
| 4. Resources | `_CodeSignature/CodeResources` (a plist of file hashes) plus the Mach-O signature from section 3 |
| 5. Package | `Payload/MyApp.app` zipped as `MyApp.ipa` |
| 6. Install | Device: `ideviceinstaller` (libimobiledevice) or Xcode's devicectl on a Mac. Simulator: `xcrun simctl install`. |

The first working target is the simulator with an ad-hoc signature, because that needs no Apple account.

### 6.1 App Store identity checks (**verify**, highest risk)

*   App Store Connect validates toolchain-identity keys in `Info.plist` (`DTPlatformName`, `DTSDKName`, `DTXcode`, `DTXcodeBuild`, `DTPlatformVersion`, `DTSDKBuild`) and the `sdk` field of `LC_BUILD_VERSION` against known Xcode releases. Without them, uploads are rejected.
*   Icons are expected as an asset catalog (`Assets.car`), produced by Apple's `actool`, whose format (BOM container) is undocumented. A `.car` writer is a large, separate project. Until it exists, a device or TestFlight build is possible only through paths that accept plain PNG icons, and the App Store path may need a Mac with Xcode for that step.
*   Treat the App Store as the final milestone, not the first. Development builds on a device and the simulator do not depend on these checks.

---

## 7. Verification and Phasing

The Windows host cannot run iOS code. Phases 1-5 run on a GitHub-hosted `macos-14` runner, in the shape of `ios-sim.yml` and `macos-corpus.yml`: an Ubuntu job builds `neper-self` and emits the Mach-O, uploads it as an artifact, and the Mac job downloads it, ad-hoc signs, runs `codesign --verify`, boots a simulator, and runs or installs it. `rcodesign` runs in the same job for the CodeDirectory diff. Each check is a `workflow_dispatch` run, so batch several checks per run. Phase 6 needs a physical iPhone, which a hosted runner lacks (a self-hosted Mac or a manual run). Phases 6 and 7 take the certificate, key and provisioning profile from encrypted GitHub secrets, never from the repository.

First workflow: `ios-sim-native.yml`, covering C225's first acceptance (a platform-7 `main` returning a code, ad-hoc signed, exit code read back from `xcrun simctl spawn`).

1. **Phase 1.** `LC_BUILD_VERSION` platform 7 Mach-O `main` returning a code, ad-hoc signed, run in the Simulator with `xcrun simctl spawn`.
2. **Phase 2.** Ad-hoc `CodeDirectory` writer. Check with `codesign -dvvv --verify`.
3. **Phase 3.** Runtime bridge: define `AppDelegate`, call `UIApplicationMain`, show a plain `UIWindow` with a colored view in the Simulator.
4. **Phase 4.** `CAMetalLayer` view, `CADisplayLink`, the existing Metal backend drawing a frame. Take a Simulator screenshot (`xcrun simctl io booted screenshot`) as the fixture.
5. **Phase 5.** Touch, `UIKeyInput`, safe area, rotation, memory warning.
6. **Phase 6.** Device build: development identity, provisioning profile, `ideviceinstaller`.
7. **Phase 7.** Distribution signing, identity keys, asset catalog, TestFlight.

---

## 8. Risks

| Risk | Mitigation |
| :--- | :--- |
| Signature one byte wrong | Diff against `rcodesign` output for the same binary. Gate every build on `codesign --verify` on a Mac. |
| `objc_msgSend` called through the wrong prototype | One typed extern per message shape, generated from a table. A fixture that sends a float-argument message and checks the value. |
| Chained-fixups bug works on macOS, fails in dyld on iOS | Test on the Simulator at each change, since simulator dyld enforces the same format. |
| App Store rejects the toolchain identity | Plan for a Mac-hosted final packaging step. Do not promise a Windows-only App Store pipeline. |
| Memory warnings arrive late | Arenas committed on demand and released in the warning callback. A jetsam-limit test on a device. |
| Apple changes UIKit lifecycle requirements | Build on `UIScene` from the start and re-check the requirement each SDK release. |
