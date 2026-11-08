# Staging, physical continuity and playback review

Use this when a shot depends on anatomy, perspective, contact, travel, recurring marks or exact prop placement. These recipes came from production failures; they improve the odds, but a successful first/last frame or a passing metric does not prove that the middle of a take works.

## One camera, one body, one room

For a person beside a door, rail, seat or other familiar object, put real dimensions and their visible consequence in the keyframe prompt: “The rail is above her head; she stands upright.” Avoid metaphors such as “folded under” when the actual clearance allows standing. For difficult perspective, draw a local guide from one camera before paying for an image. Keep its generating script with the project. Send the guide first, explicitly as geometry to repaint, followed by the character and location references. Its flat colours and stick figures must disappear in the finished painting.

An end-frame guide keeps the first frame's camera, horizon and stationary figures; move only what the action changes. Otherwise the edit model may reframe the camera to match the new guide. Review the painting against the guide before animation.

Describe a cropped or reaching body as a connected chain: facing direction, torso position (even outside the crop), shoulder → elbow → wrist → hand, then hips → knees → feet. Work out near/far limbs from the actual camera and pose. Do not prescribe a handedness from screen direction alone. Trace each visible limb back to one torso and count the fingers. If the hand cannot reach a handle without passing through a pot, turn the handle or move the prop before rewording the anatomy.

For removing one of two people, identify both the person to retain and the person to remove by clothing and screen position. For standing up or a jump, leave room for the highest head position. A medium shot that fits the seated pose may crop the standing one.

A dim room still has a floor that recedes into it, walls, soft background objects, contact shadows and shared light. A bright figure on an isolated floor patch against black can look pasted on. Describe distant lamps by apparent size, distance and blur. In a chain of closer `base:` edits, re-describe the new background; “keep the lamp” can enlarge it along with the subject. Location sheets should name where doors lead, and a doorway prompt should say what is visible through it.

## Pin what must remain true

Use `end_image` when possession of a prop, relative height, a landing position, camera travel or distant lighting must survive to the end. Make the end frame as a `base:` edit of the start, changing only the intended action. Include it in the budget from the start for difficult travel/contact shots; it is also a useful first retake strategy.

For a tracking run, the end frame should show a different stretch of the same location at the same camera height and angle. State the distance travelled and the foreground/background features that pass. Run `review:believable` as well as watching the take: changing legs in a sparse contact sheet can disguise a stationary world. The existing 0.20 frame-width/s threshold is a heuristic for tracking runs, not a universal minimum for walking or a locked camera.

Pinning the endpoints does not constrain the middle. Inspect limbs crossing faces, invented props, light flashes and background changes throughout.

## Contact and pace

For a grounded jump, landing, fall or body contact, prefer one take showing the body and its ground together. A feet insert followed by a torso shot can hide the actual take-off and break continuity. A level, locked wide view is a useful starting point for a vertical jump; tracking can be appropriate for travel. Keep shoes, contact shadows and room for the apex in frame. Write timed beats for load, push-off, airborne action and landing. The shadow stays on the ground.

Choose duration from the intended pace. Importance calls for more review and retry allowance, not automatically a longer take. Check how many seconds elapse before the action begins. Review an early action take at normal speed before scaling up production; a frame board cannot verify pacing.

For a jump, inspect feet at least eight times a second around take-off and landing, then count the actual airborne frames. Compare timing to the intended height, physical action and chosen slow-motion treatment. If only the airborne interval drags, a local edit can shorten that interval while preserving approach and landing. Preserve the downloaded original and account for every shifted shot, subtitle, voice, score and SFX cue. Never retime visible speech. `source_frames` plus `retime` trims/retimes the selected whole interval; it is not an automatic airborne-only repair.

Anime often holds a drawing for two or three frames. Examine consecutive frames over the first twelve frames before diagnosing an opening “pop”; recurring held drawings are not a reason to discard the opening. `skip_frames` now contributes to generation duration, and assembly refuses a source that cannot fill its declared slot.

For sports or other physical tasks, write the object's complete path rather than only the desired result. A miss needs a direction away from the target, not just “misses.” A pass should specify whether the receiver catches in stride. Use the intended court/field layout, distances and rules of the story's era; a full-court establishing view needs both ends, while a half-court drill may intentionally show one.

## Acting, props and stills

A roster or character entrance normally needs a small purposeful performance rather than a held action pose with moving labels. Budget for the people who must act. Keep an intentional freeze-frame, manga panel or still illustration when it fits the approved direction; record why it is static instead of treating every character still as a technical error.

For a short take, give one visible action with timing. Hands must be visible and able to reach the object they manipulate. Describe a natural whole-hand gesture and its reason: sweeping small pieces into a palm and closing a fist, rather than plucking them like a specimen. Pin the final hand/prop position when it matters.

Keep sound-only events in SFX cues. Naming a buzzer as a visual beat can make the model draw a new buzzer. Specify stable jersey markings and avoid inviting new text or equipment. Do not repeat names of absent objects unnecessarily: even exclusions can introduce them.

## Recurring logos and marks

For a mark included in the approved design, supply the actual artwork as a reference whenever it must be reproduced. Flatten a white transparent mark onto its intended backing colour if the model would otherwise see white on white. If placement must be exact, position it locally, then edit that composite with the mark as a reference so it follows cloth and perspective. Correct the character sheet first and use that accepted version downstream.

Compare front, three-quarter and side views: the mark narrows as the surface turns, without damaging the silhouette or face. Inspect other characters and the floor too; references do not prevent invented marks elsewhere. Small detailed marks can blur in a wide 768P take; simplify them or plan a closer pinned end frame when readability matters. Budget the extra image edits.

## Review record

Watch with sound, then inspect the first, middle, last and decisive action frames at useful size. Write brief answers for applicable checks; mark a check unverified when only stills were inspected.

| Check | Evidence to record |
| --- | --- |
| Scale and perspective | Person against a known-size object; camera, floor and wall lines agree |
| Anatomy and reach | Continuous limbs connected to one torso; hands can reach their targets |
| Contact | Actual take-off/landing/contact frame and shadows on the ground |
| Room and light | Shared lighting, no unintended outlines, distant lamps retain size and softness |
| Action and pace | Frame of the intended action, delay before it starts, playback judgment |
| Mouths | Close face crops through pauses; silent people do not start talking |
| Continuity | Last frame against next shot's first: feet, hands, props, possession and light |
| Colour and cuts | Inspect consecutive frames, including the tail and immediately after flashes |

Metrics identify failures; they do not certify believable performance. When the user finds an anatomy or scale fault, inspect other shots with the same setup. Retake within the approved allowance, or record the unresolved limitation. Do not invent a successful playback review from screenshots.

## Voice and local repair

`review:dialogue` already compares word multiplicities, so a repeated phrase can be flagged even when every word belongs to the script. Its Whisper call uses Fal and is paid; it is not local transcription. Listen to soft, whispered and non-Latin lines when transcription is uncertain rather than silently weakening acceptance.

Use `gate_s` for unwanted leading speech and `keep_s` for a repeated tail when a clean take remains. Rebuild `gen:dialogue`, then `gen:mix`; `dialogue:timeline` uses `speech_at` for the audible start, consistent with subtitles. `muffled: true` applies a local closed-door filter; combine with `vo: true` when no mouth should move. Listen to the filtered result before accepting it.

After a changed score, dialogue mix or mix settings, `gen:mix` fingerprints its actual audio inputs and settings and rebuilds locally. Shots and overlays refuse a missing/stale mix when dialogue exists. Music-only scenes default to -12 dB; set an explicit `music_db` for the intended balance and check neighbouring scenes by ear. Keep source/research credits in delivery notes or description text unless the approved film includes an on-screen credit sequence.
