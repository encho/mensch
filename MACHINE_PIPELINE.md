# Machine Pipeline Pattern

Active machines (`RootNote`, `DynamicVoicing`) follow an enforced phased
pipeline.

## Enforcement

`Mensch.Machine.Pipeline` behavior defines the internal machine contract:

- `build_render_context/2`
- `build_note_plan/3`
- `modulation_strategy/2`

`Pipeline.build_frame_sequence/6` orchestrates these phases and returns
`MachineFrameSequence`.

Pipeline-owned responsibilities (shared across machines):

- build note-modulation strategy context
- call strategy `with_note_modulators/4` for each planned note
- render `NoteFrame` values from `NotePlanItem` modulators via `render_note_to_frame/2`
- render note frame streams from note plans
- stitch streams into dense chord-local frame timeline
- sort frame notes by `{note_instance_id, midi_note}`
- assert end-alignment invariant (last note ends at chord end)

## Shared Common Context

`Mensch.Machine.Pipeline` computes shared timing/sample fields once and passes
them to machine `build_render_context/2` as `RenderContextCommon`:

- `sample_context`
- `chord_start_mbeat`
- `absolute_chord_start_mbeat`
- `frame_mbeats`
- `chord_duration_mbeats`

Each machine assembles a typed render context with:

- `params` (machine-specific)
- `common` (`RenderContextCommon`)

Example access: `render_context.common.chord_start_mbeat`.

## Assembler Contract

`PerformanceAssembler` calls machines with a machine-local `TimelineContext`
(`start_beat = 0`) and passes absolute timeline anchor via
`absolute_chord_start_mbeat` in `opts`.

Implications:

- machine scheduling is chord-local
- modulation can still anchor to sample-global time
- machines return local frames; assembler shifts to global timeline

## Phase Summary

1. Intake and normalize machine params.
2. Build typed render context from shared common fields.
3. Build raw `NotePlanItem` values (`start_mbeat`, `duration_mbeats`,
   tags/provenance).
4. Resolve machine note-modulation strategy (`modulation_strategy/2`).
5. Build strategy context and attach modulation functions by calling strategy
  `with_note_modulators/4` for each note (`pressure_modulator` /
  `slide_modulator` / `bend_modulator`).
6. Pipeline renders per-note frames through `render_note_to_frame/2`
  (machine-agnostic).
7. Pipeline stitches streams into dense frame timeline over
   `chord_start_mbeat..(chord_start_mbeat + chord_duration_mbeats)`.
8. Pipeline sorts notes per frame by `{note_instance_id, midi_note}`.
9. Pipeline asserts end-alignment invariant.
10. Return local `MachineFrameSequence`.

## Naming Conventions

- `start_mbeat`: per-note local start.
- `duration_mbeats` (`NotePlanItem`): per-note local lifecycle duration.
- `chord_start_mbeat`: local chord-entry start.
- `chord_duration_mbeats`: local chord-entry duration.
- `frame_mbeats`: frame step.
- `absolute_chord_start_mbeat`: global/sample timeline anchor.

## Machine Notes

- `RootNote`: one root note, pressure baseline fixed to `0`; pressure comes
  from the configured note-modulation strategy.
- `DynamicVoicing`: inversion-transition lifecycles with per-note
  `duration_mbeats` carried in `NotePlanItem`; note-expression shaping is
  delegated to the configured note-modulation strategy.

## Current Simplifications

- `phase` is no longer part of note frames.
- Machines no longer implement `render_note_frame/3`; frame rendering is fully
  centralized in pipeline.
- Playback/export expression emission is now gated by `note_off` only.
