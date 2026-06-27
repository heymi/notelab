# Voice Recording Waveform Design

## Goal

Replace the current bar-style recording meter in the home recording overlay with a screenshot-inspired dynamic waveform: a thin center line with colorful, soft wave peaks that respond to live microphone input.

## Scope

- Change only the active recording overlay shown while `voiceCoordinator.isRecording == true`.
- Keep the home bottom voice button unchanged.
- Keep recording, cancel, stop, notebook selection, save, transcription, and AI organization behavior unchanged.
- Reuse the existing `VoiceNoteCoordinator.inputLevel` meter; do not add a new audio engine or sampling path.

## Recommended Approach

Add a small SwiftUI waveform view inside `VoiceRecordingOverlay`, replacing the existing 18 capsule bars. The view uses `TimelineView` plus `Canvas` to draw:

- A subtle horizontal center line.
- Four or five colored wave lobes distributed around the center.
- Height, width, opacity, and slight phase movement driven by the smoothed `level` value.

This keeps the implementation local to the visual layer while preserving the real audio-driven behavior already in `VoiceNoteCoordinator.updateMeter()`.

## Visual Behavior

When recording starts, the overlay continues to show the cancel button, recording label, elapsed timer, and stop button. The meter area becomes the waveform. Quiet input should settle close to the center line. Louder input should expand the colored lobes outward, with mild flowing motion so it feels alive without looking noisy.

The palette should echo the reference image: teal/green as the main accent, with smaller blue, rose, and violet highlights. Colors should sit inside the existing dark material overlay instead of changing the surrounding app theme.

## Accessibility

Respect Reduce Motion. When motion is reduced, the waveform should still reflect the current level but avoid continuous phase animation. The center line and a subdued static waveform are enough.

## Files Expected To Change

- `NoteLab/VoiceNoteViews.swift`: replace the current bar meter with the new waveform view, likely as a private nested or file-local SwiftUI view.

No data models, persistence, audio recording logic, AI paths, or navigation files should change.

## Verification

Run the smallest reliable build check for the iOS target. Then verify on simulator or device:

- Starting voice input shows the recording overlay.
- Speaking changes the waveform amplitude.
- Cancel still discards the recording.
- Stop still opens notebook selection for recordings longer than one second.
- Reduce Motion does not leave a constantly animated waveform.

## Non-Goals

- Do not redesign the bottom navigation voice button.
- Do not alter voice note storage, transcription, or AI cleanup.
- Do not add a reusable animation framework or new dependency.
- Do not implement playback waveform visualization in saved voice notes.
