# QQ 9.3.65.605 analysis notes

Analyzed input: decrypted ARM64 `QQ`, bundle ID `com.tencent.mqq`, minimum iOS
15.0, `LC_ENCRYPTION_INFO_64.cryptid = 0`. Addresses below are unslid virtual
addresses for this build only. The plugin uses selectors, never these addresses.

## Dice identity

The bundled `face_config.json` identifies QSid 358 as the dice, with pack ID 1,
sticker ID 33, and AniStickerType 2. It matches the interactive-emoji screenshot.

## Live interactive send path (0.2.0)

On iOS 15.3.1 with QQ 9.3.65.605, tapping the interactive dice reaches
`-[FaceRichBoard.NTAIOFaceRichBoardViewModel onSendLottieEmojiWithContact:emojiId:]`.
The runtime encoding is `v28@0:8@16I24`: contact object first, unsigned emoji ID
second. Its Objective-C wrapper is at `0x1044231c8`. The observed stack proceeds
through `0x104422f44`, the builder at `0x108f1fd08`, and the same face factory at
`0x110bac1d0`. This path bypasses `NTFaceSendHandler` completely.

Version 0.2.0 intercepts this entry point before construction, retaining the
contact and sender in the picker callback. The legacy hook remains available.
Device testing confirmed the picker and initial result assignment work. The
server subsequently overwrote those results, as described below.

## Server result replacement (0.3.0)

Tracing `MSFReqModel.data` and `MSFRspModel.recvData` for `MessageSvc.PbSendMsg`
identified the overwrite. These buffers have a four-byte big-endian length
prefix, including the prefix itself, before the protobuf message.

With the default stickerType 2, selecting 6 produced a successful response whose
field 13 contained dice 358 and resultId "3". QQ then updated the message to 3,
matching the user-visible result. Earlier tests produced 2 and 1; changing only
randomType from 1 to 0 still produced 4.

A scoped experiment setting stickerType to 0 produced an outgoing rich-text
common element (service 37) with pack "1", sticker "33", face 358, source 1,
stickerType 0, resultId "6", and randomType 1. The server acknowledged success
without field 13, so no replacement dice result was supplied. No incoming data
or rendering methods were modified. The user confirmed both sender and
recipient displayed 6. Further scoped tests sent 1 through 5: every outgoing
result matched the selection, every response acknowledged success, and none
contained field 13. The user reported correct behavior. All six values were
thus covered across these temporary runtime tests. The user subsequently
reinjected the compiled 0.3.0 and confirmed chosen results worked. Later
forwarding and preview tests exposed the compatibility regressions below.

Version 0.3.0 applies this additional assignment only to the same outgoing face
already selected by the scoped hook. It verifies the setter ABI before installing.
Tests cover all six choices and preserve type 2 on unrelated, additional, and
unscoped faces.

## Native forwarding and preview regression

The user observed normal dice forwarding from 5 to 4, while a selected 6 stayed
6. A subsequent read-only trace captured the actual single-message forward via
`OCIKernelMsgService forwardMsgWithComment:srcContact:dstContacts:commentElements:msgAttributeInfos:cb:`.
The normal message used service 37, business 2, stickerType 2, randomType 0,
and no resultId. The successful response supplied result 2 in field 13.
The plugin message used business 0, stickerType 0, randomType 1, and result 6;
the server accepted it without a replacement result.

Thus changing stickerType in 0.3.0 changed both the inner sticker type and the
outer business discriminator. The original experiment did not distinguish
which of those prevented server replacement. The new trace proves that native
forwarding clears the result, while the type-0 message is copied unchanged.

Screenshots also showed a placeholder when opening plugin dice and different
desktop fallback text. Static analysis of `AniStickerView` at `0x10b5e9fd4`
shows separate type-2 random-animation and type-1 animation branches; type 0
does not take either ordinary branch. Runtime resource tracing observed the
regular loader and the result-aware loader on the two kinds of dice. Both
returned existing resources, so missing files alone do not explain the issue.

## Separating native type from send business (0.4.0)

A temporary experiment changed the outgoing inner stickerType back to 2 while
keeping outer business 0. It used Google's protobuf parser to preserve unknown
fields. Captured sends with results 6, 5, and 3 all retained their selected
results, and successful responses contained no replacement field 13. The
user reported success after being asked to check receipt, preview, and forwarding
on an unmodified receiving client. No incoming payload or rendering was patched.

Version 0.4.0 leaves the locally constructed face's native type unchanged.
`MSFReqModel.data` is adapted only for `MessageSvc.PbSendMsg`. The adapter uses
QQ's `GPBCodedInputStream`, with ABI checks, to navigate:

`Send[3] -> Body[1] -> RichText[2] -> Element[53] -> CommonElement[3]`.

It requires service 37, business 2, pack "1", sticker "33", face 358, source 1,
stickerType 2, randomType 1, and a one-character result from "1" through "6".
Exactly one matching element is allowed. It changes only the business varint's
single byte from 2 to 0; all lengths and other bytes are retained. Native
forwarding clears the result and therefore does not match. Type-0 history,
other commands, other emoji, malformed frames, and ambiguous duplicate fields
are passed through. Results are cached per request with a copy of the input,
so repeated reads and in-place input changes cannot reuse stale output.

The temporary experiment started with 0.3.0's local type-0 object and restored
type 2 on the wire. The compiled implementation instead starts with native
type 2 locally and changes only business on the wire. Its outgoing field values
are equivalent, but the compiled dylib and sender preview need a fresh device
acceptance test. The temporary tests do not establish compatibility with every
QQ client, chat type, or future server revision.

## Legacy send path

1. `-[NTFaceSendHandler sendSuperEmojiWithSid:context:]`, `0x1099653ec`,
   encoding `v28@0:8I16@20`, reads `context.chatInfo` and invokes the service's
   `sendSuperEmojiWithSid:chatInfo:` class method through Objective-C dispatch.
2. `_TtC26FaceRichBoardServiceModule20FaceRichBoardService`, wrapper
   `0x1044a685c`, calls Swift implementation `0x1044a6778`.
3. That implementation calls element builder `0x108f1f698` synchronously, which
   calls factory `0x110bac040`.
4. The factory allocates `OCMsgElement` and `OCFaceElement`, sets the face ID,
   text, sticker ID/type, pack ID, face type and source type, then invokes
   `-[OCMsgElement setFaceElement:]` before returning the completed element.
5. The service subsequently submits that element array through QQ's sender.

The plugin pauses step 1 for selection and puts a thread-local scope around the
original invocation. At step 4 it assigns `resultId` and `randomType` to the
first face 358 only. The values stay attached to the outgoing object even if
QQ later submits it on another queue. The scope ends as soon as the original
invocation returns, including exceptional exits.

## Fields and limits

- `-[OCFaceElement faceIndex]`: `I16@0:8`, unsigned int.
- `-[OCFaceElement setResultId:]`: `v24@0:8@16`, object (NSString).
- `-[OCFaceElement setRandomType:]`: `v24@0:8@16`, object (NSNumber).
- `-[OCFaceElement setStickerType:]`: `v24@0:8@16`, object (NSNumber).
- `-[OCMsgElement setFaceElement:]`: `v24@0:8@16`.

The 0.4.0 outgoing values are result strings `1` through `6`, randomType 1,
native stickerType 2, and outer business 0, as described above.
QQ's own `AniStickerAtomMsgData.convertToMsgRecord` implementation also copies
the result string into `OCFaceElement.resultId` (call at `0x1027cc17c`).
Public protocol code corroborates a string result and randomType 1 for large
interactive faces:
https://github.com/NapNeko/NapCatQQ/blob/main/packages/napcat-core/packet/message/element.ts

This corroboration does not prove the iOS kernel or server will preserve those
values, or establish a device-tested 1:1 animation mapping. That is deliberately
left as an explicit device acceptance test, not a claim of proven operation.
QQ may hot-patch Swift entry points; the version and method guards cannot detect
every such behavioral change. `patchedElements=0` identifies a missed hook.

No receive-side rendering hooks, global random hooks, or hard-coded process
addresses are used. Only the matching outgoing request payload is adapted.
The current adapter covers the inspected
interactive-emoji path; legacy market-face dice and other QQ builds are outside
this adapter's scope.

## Loading diagnosis

On the test device, `Frameworks/QQtouzi.dylib` existed but the running QQ process
had not loaded it. The QQ executable had no load command for this dylib. Loading
the bundled library with the debugger succeeded and installed its hooks, proving
that copying the file into Frameworks alone had not activated the plugin.
An injector must add a load command (or provide another functioning loader),
handle signing, and restart QQ. A successful file copy is insufficient.
