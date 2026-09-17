# QQ 9.3.65.605 analysis notes

Analyzed input: decrypted ARM64 `QQ`, bundle ID `com.tencent.mqq`, minimum iOS
15.0, `LC_ENCRYPTION_INFO_64.cryptid = 0`. Addresses below are unslid virtual
addresses for this build only. The plugin uses selectors, never these addresses.

## Dice identity

The bundled `face_config.json` identifies QSid 358 as the dice, with pack ID 1,
sticker ID 33, and AniStickerType 2. It matches the interactive-emoji screenshot.

## Send path

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
