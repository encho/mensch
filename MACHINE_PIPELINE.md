# Machine Pipeline Pattern

This project's machines (for example RootNote) follow a consistent render pipeline.

## 1. Intake and Normalize Inputs

- Receive `chord_spec`, `sample_context`, `timeline_context`, and `opts`.
- Fetch machine params from `opts`.
- Hydrate/normalize params so downstream code can assume valid shapes.

## 2. Build Render Context

- Build a machine-specific render context struct once.
- Include:
  - normalized params
  - sample context
  - frame step (`frame_mbeats`)
  - local chord duration (`chord_duration_mbeats`)
  - absolute chord start (`absolute_chord_start_mbeat`) for sample-anchored modulation

This keeps frame rendering independent from raw external inputs.

## 3. Compute Local Timing

- Compute frame step (`frame_mbeats`).
- Compute local entry start (`start_mbeat`) and local duration (`duration_mbeats`).
- Snap timing to frame grid.

After these values are known, place stable per-render timing values into render context
so note/frame functions do not need separate repeated arguments.

Machine note scheduling is local to the entry/chord timeline.

## 4. Plan Notes

- Create one or more `NotePlanItem` values.
- Fill identity/provenance fields (`machine_id`, `note_instance_id`, `degree_index`, tags).
- Set `start_mbeat` for each note.
- Optionally attach ADSR in a later stage.

## 5. Render Per-Frame Note States

- For each note, iterate frame times from `note.start_mbeat` to note end.
- Compute local elapsed time (`at_mbeat - note.start_mbeat`).
- Read modulation and timing invariants from render context.
- Evaluate modulation (pressure/slide/bend) using local elapsed time + render context.
- Emit `NoteFrame` values with `note_on`/`note_off`, phase, and expression.

## 6. Stitch and Densify Frames

- Group rendered note events by `at_mbeat`.
- Produce dense frame list across full local duration.
- Ensure empty frames still exist so playback/export sees a complete timeline.

## 7. Assert Invariants

- Check machine invariants before returning (for example last note ends at chord end).
- Raise clear errors if violated.

## 8. Return MachineFrameSequence

- Return local `MachineFrameSequence`.
- Global sample placement (shifting by absolute entry start) is handled by the assembler layer, not by machine scheduling.

## Current Naming Conventions

- `start_mbeat`: per-note local start in the machine/chord-local timeline.
- `chord_duration_mbeats`: local chord-entry duration for the current machine render.
- `frame_mbeats`: frame step for the current machine render.
- `absolute_chord_start_mbeat`: global/sample timeline anchor for the chord entry.
