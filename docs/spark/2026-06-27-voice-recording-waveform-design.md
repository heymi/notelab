# Voice Recording Waveform Design

## Goal

Make the home voice-recording waveform feel like a system recorder: sensitive, low-latency, and visibly tied to the user's mouth. The reference screenshot remains the visual direction, but responsiveness wins over static similarity.

## Problem With The Previous Direction

The earlier visual-only approach assumed `AVAudioRecorder` metering was a reliable source for the animation. Real-device testing showed the opposite: the shape could look closer to the reference while still feeling fake because the waveform did not move clearly with speech.

The revised design treats that as a data-source problem, not an animation-tuning problem.

## Scope

- Replace the recording input path inside `VoiceNoteCoordinator` with one `AVAudioEngine` input pipeline.
- Use the same live PCM buffers for both writing the recording file and calculating `inputLevel`.
- Keep the existing public state surface: `phase`, `elapsed`, `inputLevel`, `stopRecording()`, `discardCurrentRecording()`, and `savePendingRecording(...)`.
- Keep the current saved voice-note flow: temporary audio file -> attachment storage -> Speech transcription -> AI organization.
- Keep the active recording overlay as the only visual surface changed for this waveform work.

## Recommended Approach

Use `AVAudioEngine.inputNode.installTap` as the single source of truth:

1. Configure `AVAudioSession` for recording, prefer the built-in microphone, and request a low IO buffer duration.
2. Start `AVAudioEngine`.
3. On each input buffer:
   - Write the buffer to a temporary audio file.
   - Calculate RMS and peak energy from the exact same buffer.
   - Smooth the energy with fast attack and slower release.
   - Publish the normalized value through `VoiceNoteCoordinator.inputLevel`.
4. On stop, close the audio file cleanly and continue into the existing notebook-selection/save flow.
5. On cancel or short recording, stop the engine and remove the temporary file.

This removes the split-brain state where one API records audio and another API tries to guess meter values.

## File Format

Use `.caf` with linear PCM for the first implementation. It is the simplest reliable format for direct `AVAudioPCMBuffer` writing, and it avoids pretending raw PCM is an `.m4a`.

Save the attachment with a `.caf` filename and `audio/x-caf` MIME type. Add `caf -> audio/x-caf` to `AttachmentStorage.mimeType(for:)` so imported/reused CAF files are classified consistently.

Do not keep a `.m4a` filename unless the implementation actually writes MPEG-4 AAC.

## Visual Behavior

The overlay keeps the same controls: cancel, "正在录音", waveform, elapsed time, stop.

The waveform should:

- Sit near a thin center line in silence.
- Show small but visible movement for quiet speech.
- Expand immediately on normal speech.
- Spike quickly on plosives or louder syllables.
- Fall back quickly enough that pauses feel live, not sluggish.
- Avoid self-running loops when `inputLevel` is unchanged.

The reference visual language remains: a thin center line with teal/green, blue, rose, and violet lobes. The lobe geometry can be simplified if that makes the response clearer.

## Quality Bar

The implementation is not done until it passes real-device behavior checks:

- Speaking directly at the phone from normal distance causes obvious waveform movement within about one frame of perceived delay.
- Whisper/soft speech causes a smaller but still visible change.
- Silence returns close to the center line.
- The elapsed timer still advances correctly.
- Stop after more than one second still opens notebook selection.
- Cancel still discards the temporary recording.
- Saved audio can still play back.
- Transcription still receives a valid audio file.

## Error Handling

- If microphone permission is denied, keep the existing error message.
- If the engine cannot start, fail recording with the existing recorder-unavailable path.
- If file writing fails, stop the engine and fail instead of silently showing a fake waveform.
- Always remove the input tap and stop the engine on stop, cancel, short recording, and failure.

## Accessibility

Respect Reduce Motion. Reduced Motion should not run decorative phase movement. It may still update amplitude from real input because that is functional feedback, not decoration.

## Files Expected To Change

- `NoteLab/VoiceNoteCoordinator.swift`: replace recorder-based capture/metering with a unified `AVAudioEngine` input pipeline, preserving existing coordinator API and state machine.
- `NoteLab/VoiceNoteViews.swift`: keep the screenshot-inspired waveform but drive it only from `inputLevel` and recent samples, with no fake loop.
- `NoteLab/Storage/AttachmentStorage.swift`: add `caf -> audio/x-caf` MIME handling.

## Verification

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project NoteLab.xcodeproj -scheme "NoteLab Local StoreKit" -destination 'generic/platform=iOS' build
```

Then install and test on `Strictly's iPhone`:

```bash
ios-deploy --id 00008140-000C6D403AC3801C --bundle <built NoteLab.app>
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun devicectl device process launch --device 00008140-000C6D403AC3801C com.psg.NoteLab
```

Manual verification must include speaking at the phone while watching the waveform. Build success alone is not enough.

## Non-Goals

- Do not redesign the full home screen.
- Do not add a third-party waveform or audio dependency.
- Do not build saved-note playback waveforms.
- Do not keep decorative animation that moves when the input level is flat.
