# QQtouzi

An experimental standalone iOS dylib for the built-in interactive dice in QQ
9.3.65 (build 9.3.65.605), ARM64, iOS 15 or later.

Tap QQ's interactive dice, select 1-6 in the native dialog, or cancel. The plugin
sets the result on the outgoing dice message. Version 0.4.0 preserves the native
sticker type and changes only the outer send business field to avoid a new
server-generated result.
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

- Version 0.4.0 keeps `stickerType=2`, pack "1", sticker "33", face 358,
  `randomType=1`, and the selected result. Only the enclosing service-37
  `businessType` changes from 2 to 0. QQ's existing protobuf reader locates that
  field; all other bytes, unknown fields, and lengths remain unchanged.
- Temporary device tests sent native-type results 6, 5, and 3 with business 0.
  Each was acknowledged without a replacement result. After being asked to
  check receipt, preview, and single-message forwarding on an unmodified
  receiving client, the user reported that the test worked. This is evidence
  for the temporary wire experiment; the compiled 0.4.0 still needs reinjection
  and a repeat acceptance test, including the sender's own preview.
- Version 0.3.0 fixed chosen results for both sender and recipient, including
  the user's installed-dylib test. However, its `stickerType=0` also changed the
  message's meaning: forwarding retained the result, preview could show a
  placeholder, and desktop fallback differed from native dice. It does not
  provide full native compatibility. Messages already sent by 0.3.0 are not
  repaired by installing 0.4.0; test newly sent messages.
- Version 0.2.0 adds the modern interactive panel's send entry point, identified
  by tracing a real dice tap. Version 0.1.0 only hooked a legacy send path that
  the tested interactive panel bypasses.
- The send method, dice ID, element construction, and Objective-C signatures
  were identified in the supplied decrypted QQ 9.3.65.605 executable.
- GitHub Actions runs macOS tests of outgoing result assignment, non-dice and
  incoming-message isolation, nested scopes, concurrency, and ABI guards.
  Wire tests use Google's protobuf runtime and cover all six results, native
  forwarding without a result, unknown fields, malformed data, and request
  caching. CI also builds and verifies the ARM64 iOS dylib. A successful build
  does **not** establish end-to-end behavior.

Test 1 through 6 with a second account on an unmodified QQ client. Check both
private and group chats, cancellation, consecutive sends, and incoming dice.
Reopen chat history to check that the result persists. Do not infer success
solely from the sender's animation. Open the new dice's preview on both clients,
then single-forward it from the unmodified client and check for a fresh roll.

If no picker appears, first verify that `QQtouzi.dylib` is in QQ's **loaded
modules**, not just its Frameworks folder. The injector must add a dylib load
command or provide a working loader, and QQ must be fully restarted. This was
a separate cause of the missing picker on the test device.

Console messages have the prefix `[QQtouzi]`. Startup should log
`0.4.0 interactive dice hook installed`. A chosen send should log
`Requested=N patchedElements=1`. Zero patched elements means the live send path
differs from the analyzed executable; that send may retain QQ's normal random
behavior. Different QQ builds are disabled by the version guard.

## Build

Push to `main` or run the workflow manually. No local Apple toolchain is needed.
On a Mac with Xcode installed, run `bash scripts/build.sh`. Wire tests fetch
protobuf 3.21.12 at a pinned commit into `build/protobuf`; network access is
needed on the first run. This test dependency is not included in the dylib.

The IPA and extracted QQ binaries are not part of this repository.
See [analysis notes](docs/analysis.md) for the evidence and limitations.
