# iOS cross-compilation

Status: not targeted. The language specification currently excludes iOS
rather than scheduling it as a deferred host.

Neper could compile target-independent code and emit ARM64 iOS Mach-O objects
on Windows. It should not promise a completely Apple-free path to an
installable or App Store-ready application: device installation, entitlements
and distribution are controlled by Apple signing, provisioning and current SDK
requirements.

The recommended future pipeline is:

```text
Windows: Neper source -> arm64 iOS Mach-O objects or library
macOS:   final link -> app bundle -> sign -> validate -> upload
```

This keeps compilation on Windows while leaving the smallest policy-sensitive
step in the supported Apple toolchain.

## Why iOS differs from macOS and Android

An unsigned macOS command-line executable can be useful, and Android permits a
self-signed APK. iOS has no equivalent general-purpose unsigned application
path. A physical-device application needs an App ID, signing identity and
provisioning profile. Its signed entitlements must be allowed by that profile.

App Store Connect also imposes a current Xcode and iOS SDK floor. Reproducing
the bytes written by Apple's tools would not remove that submission rule.
Therefore "no additional software installed on Windows" is attainable for the
Neper compilation phase, not for the complete official distribution pipeline.

## Windows compilation boundary

A useful first target would emit a relocatable Mach-O object or static library:

```text
target: aarch64-ios
output: relocatable Mach-O object or static library
```

That phase may own:

- AArch64 instruction selection, register allocation and relocations;
- the Apple ARM64 calling convention;
- iOS Mach-O object sections, symbols, DWARF and unwind information;
- target layout, conditional compilation and API availability checking; and
- Neper runtime code that does not depend on application provisioning.

It need not own final framework resolution, application signing or App Store
upload. A generated minimal Xcode project or finalizer can consume the object,
select the installed SDK, link the requested frameworks and produce the signed
archive.

## Work required for an iOS target

Beyond the AArch64 and Mach-O work shared with macOS, a useful iOS target needs:

- `.Ios` in `target.Os`, an `ios` source suffix and `lib/e/os.ios.e`;
- sandbox-aware file, process, thread, clock and memory behaviour;
- Objective-C runtime calling support and an application lifecycle bridge;
- UIKit bindings and an iOS implementation of `e.ui`;
- framework imports with deployment-target and availability metadata;
- application bundle metadata, `Info.plist`, resources, icons and asset
  catalogs;
- entitlements and provisioning-profile inputs;
- device code signatures, including the required entitlement forms; and
- physical-device, simulator, TestFlight and App Store validation.

Swift is not a prerequisite: the initial bridge can use C and the Objective-C
runtime. Avoiding Swift does not remove UIKit, bundle, signing or provisioning
work.

## Signing and provisioning

The compiler must never invent a release identity or silently widen
entitlements. A finalizer receives:

- the bundle identifier and deployment target;
- an Apple-issued provisioning profile;
- the matching certificate and private key; and
- the exact entitlement set requested by the application.

It verifies that every requested entitlement is authorized by the profile,
then delegates the supported signing and archive flow to the current Apple
toolchain. Development, ad-hoc, TestFlight and App Store distributions are
distinct modes and must not share accidental defaults.

## Delivery assessment

After the shared AArch64 emitter and Mach-O object writer exist, Windows
emission of an `aarch64-ios` object/library plus a generated Xcode finalizer is
roughly a two-to-four engineer-week increment.

A minimal signed application adds the OS surface, lifecycle, bundle and
provisioning work. A production target with `e.ui`, resources, device coverage
and App Store maintenance is a six-to-twelve-month project and carries an
ongoing annual SDK compatibility cost. Reimplementing Xcode's complete final
link, signing and packaging pipeline is not recommended.

Current Apple requirements are recorded in the official documentation for
[provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles),
[App Store uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[SDK submission floors](https://developer.apple.com/news/upcoming-requirements/?id=04282026a),
and [Xcode system requirements](https://developer.apple.com/xcode/system-requirements).
The normative Neper scope remains in [`spec.md`](spec.md); this note is an
evaluation, not a change to that scope.
