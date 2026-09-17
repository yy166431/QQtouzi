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
The picker and final transmitted result still require validation of this build.

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
- `-[OCMsgElement setFaceElement:]`: `v24@0:8@16`.

The candidate wire values are result strings `1` through `6` and randomType 1.
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

No receive-side rendering hooks, global random hooks, raw network packets, or
hard-coded process addresses are used. The current adapter covers the inspected
interactive-emoji path; legacy market-face dice and other QQ builds are outside
this adapter's scope.

## Loading diagnosis

On the test device, `Frameworks/QQtouzi.dylib` existed but the running QQ process
had not loaded it. The QQ executable had no load command for this dylib. Loading
the bundled library with the debugger succeeded and installed its hooks, proving
that copying the file into Frameworks alone had not activated the plugin.
An injector must add a load command (or provide another functioning loader),
handle signing, and restart QQ. A successful file copy is insufficient.
