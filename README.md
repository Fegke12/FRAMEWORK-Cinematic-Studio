# FRAMEWORK Cinematic Studio — source handoff

This branch contains camera-source references for integrating the project in Work and Roblox Studio. The repository's `main` branch was not modified during this upload.

## Source files

| File | Provenance | Status |
| --- | --- | --- |
| [VehicleRig_V3.1_from_chat.luau](sources/VehicleRig_V3.1_from_chat.luau) | Transcription of V3.1 from our ChatGPT conversation, with mount/ActiveTrack stability rules retained | User reported V3.1 working in their Roblox place, **this uploaded transcription has not been separately tested** |
| [HeadFreeCam_V5.1_reference.luau](sources/HeadFreeCam_V5.1_reference.luau) | New replacement/reference from remembered V5.1 feature description | **Not the exact original FreeCam V5.1**; not tested |
| [SOURCE_HANDOFF.md](docs/SOURCE_HANDOFF.md) | Requirements for Work integration | Specification |

## Core requirement

The Vehicle Rig's camera **position must only depend on its mounting point on the user's own vehicle**. ActiveTrack may influence **camera rotation, focus and FOV**, but not position. Preserve car controls.

## Intended project

FRAMEWORK will combine FreeCam + Vehicle Rig in one modular launcher with a new professional dark UI, common camera/input lifecycle, presets, tracking tools, and consistent cleanup. The source files in this branch are **not a completed integrated launcher**.

## Testing / platform rules

No Roblox Studio runtime validation or Xeno compatibility validation was performed during this transfer. A GitHub repository or permission from game moderators is not authorization from Roblox to use unofficial executors; a built-in Studio LocalScript is the cleaner route if the developers approve it.
