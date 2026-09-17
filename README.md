# QQtouzi

An experimental standalone iOS dylib for the built-in interactive dice in QQ
9.3.65 (build 9.3.65.605), ARM64, iOS 15 or later.

Tap QQ's interactive dice, select 1-6 in the native dialog, or cancel. The plugin
sets the result on the outgoing dice message before QQ continues sending it.
Other emoji and messages outside that send operation are unchanged.

## Download and inject

1. Open this repository's **Actions** tab and the latest successful
   **Build iOS dylib** run.
2. Download **QQtouzi-arm64**, then extract `QQtouzi.dylib`.
3. Import the dylib into your TrollStore-compatible injector and inject it into
   the analyzed QQ version. Restart QQ completely.
4. Open a chat and select the dice under interactive emoji. Choose a result.

This is an injected library, not a standalone app or an IPA. It uses the
Objective-C runtime and system frameworks; Cydia Substrate, Substitute, and
ElleKit are not required. The artifact is ad-hoc signed; the injector must
handle the target application's loading/signing requirements.

## Verification status

- The send method, dice ID, element construction, and Objective-C signatures
  were identified in the supplied decrypted QQ 9.3.65.605 executable.
- GitHub Actions runs macOS tests of outgoing result assignment, non-dice and
  incoming-message isolation, nested scopes, concurrency, and ABI guards.
  It builds and verifies the ARM64 iOS dylib.
- Injection, actual QQ execution, server acceptance, animation-to-result mapping,
  and the recipient's displayed result require device testing. A successful
  build does **not** establish that QQ's server preserves the selected result.

Test 1 through 6 with a second account on an unmodified QQ client. Check both
private and group chats, cancellation, consecutive sends, and incoming dice.
Reopen chat history to check that the result persists. Do not infer success
solely from the sender's animation.

Console messages have the prefix `[QQtouzi]`. A chosen send should log
`Requested=N patchedElements=1`. Zero patched elements means the live send path
differs from the analyzed executable; that send may retain QQ's normal random
behavior. Different QQ builds are disabled by the version guard.

## Build

Push to `main` or run the workflow manually. No local Apple toolchain is needed.
On a Mac with Xcode installed, run `bash scripts/build.sh`.

The IPA and extracted QQ binaries are not part of this repository.
See [analysis notes](docs/analysis.md) for the evidence and limitations.

