# Machine Pipeline Pattern

This project's active machines (`RootNote`, `DynamicVoicing`) follow a consistent
render pipeline.

## Assembler Contract (Important)

`PerformanceAssembler` calls machines with a machine-local `TimelineContext`
where `start_beat = 0`, and passes the real global start as
`absolute_chord_start_mbeat` in `opts`.

Consequences:

- machine-local scheduling always starts from chord-local time
- sample/global anchoring is available for modulation phase alignment
- machines return local frame sequences; assembler shifts them to global time

## 1. Intake and Normalize Inputs

- Receive `chord_spec`, `sample_context`, `timeline_context`, and `opts`.
- Fetch machine params from `opts`.
- Hydrate/normalize params so downstream code can assume valid shapes.

## 2. Build Render Context

- Compute frame step (`frame_mbeats`).
- Compute local chord start (`chord_start_mbeat`) and local chord duration (`chord_duration_mbeats`).
- Snap timing to frame grid.
- Build a machine-specific render context struct once.
- Include:
  - normalized params
  - sample context
  - local chord start (`chord_start_mbeat`)
  - frame step (`frame_mbeats`)
  - local chord duration (`chord_duration_mbeats`)
  - absolute chord start (`absolute_chord_start_mbeat`) for sample-anchored modulation

This keeps frame rendering independent from raw external inputs.

The common non-param fields/validation for render context are centralized in
`Mensch.Machine.RenderContextCommon`; each machine still owns its typed
render-context struct so param types remain machine-specific.

After these values are known, place stable per-render timing values into render context
so note/frame functions do not need separate repeated arguments.

Machine note scheduling is local to the entry/chord timeline.

In normal pipeline usage, `start_mbeat` resolves to `0` because the assembler
normalizes the machine input timeline to local zero.

Machines now carry this value explicitly as `chord_start_mbeat` in render
context so they can also render correctly when called directly with non-zero
local starts.

## 3. Plan Notes

- Create one or more `NotePlanItem` values.
- Fill identity/provenance fields (`machine_id`, `note_instance_id`, `degree_index`, tags).
- Set `start_mbeat` for each note.
- Set `duration_mbeats` for each note.
- Optionally attach ADSR in a later stage.

`NotePlanItem.duration_mbeats` is the canonical per-note lifecycle length.
It is note-local and may differ from `chord_duration_mbeats`.

## 4. Render Per-Frame Note States

- For each note, iterate frame times from `note.start_mbeat` to note end.
- Compute local elapsed time (`at_mbeat - note.start_mbeat`).
- Read modulation and timing invariants from render context.
- Evaluate modulation (pressure/slide/bend) using local elapsed time + render context.
- Drive note lifecycle (`phase`, `note_off`) from `note.duration_mbeats`.
- Emit `NoteFrame` values with `note_on`/`note_off`, phase, and expression.

Frame stitching/densification uses the local chord window:

- start: `chord_start_mbeat`
- end: `chord_start_mbeat + chord_duration_mbeats`

## 5. Stitch and Densify Frames

- Group rendered note events by `at_mbeat`.
- Produce dense frame list across full local duration.
- Ensure empty frames still exist so playback/export sees a complete timeline.

## 6. Assert Invariants

- Check machine invariants before returning (for example expected end alignment rules).
- Raise clear errors if violated.

## 7. Return MachineFrameSequence

- Return local `MachineFrameSequence`.
- Global sample placement (shifting by absolute entry start) is handled by the assembler layer, not by machine scheduling.

## Current Naming Conventions

- `start_mbeat`: per-note local start in the machine/chord-local timeline.
- `chord_start_mbeat`: local chord-entry start used as the render window origin.
- `duration_mbeats` (on `NotePlanItem`): per-note local lifecycle duration.
- `chord_duration_mbeats`: local chord-entry duration for the current machine render.
- `frame_mbeats`: frame step for the current machine render.
- `absolute_chord_start_mbeat`: global/sample timeline anchor for the chord entry.

## Current Machine Notes

- `RootNote`: single root note, pressure baseline fixed to `0`; pressure motion is
  produced by `lfo_pressure` modulation only.
- `DynamicVoicing`: plans multiple note lifecycles across voicing transitions;
  per-note durations are carried directly in `NotePlanItem.duration_mbeats`.
