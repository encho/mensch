# Machine Pipeline Pattern

Active machines (`RootNote`, `DynamicVoicing`) follow an enforced phased
pipeline.

## Enforcement

`Mensch.Machine.Pipeline` behavior defines the internal machine contract:

- `build_render_context/2`
- `build_note_plan/3`
- `render_note_frame_stream/2`
- `stitch_note_frame_streams/2`
- `assert_invariants/2`

`Pipeline.build_frame_sequence/6` orchestrates these phases and returns
`MachineFrameSequence`.

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
3. Build `NotePlanItem` values (`start_mbeat`, `duration_mbeats`, tags/provenance).
4. Render per-note frame streams (`note_on`, `note_off`, phase, expression).
5. Stitch streams into dense frame timeline over
   `chord_start_mbeat..(chord_start_mbeat + chord_duration_mbeats)`.
6. Assert machine invariants.
7. Return local `MachineFrameSequence`.

## Naming Conventions

- `start_mbeat`: per-note local start.
- `duration_mbeats` (`NotePlanItem`): per-note local lifecycle duration.
- `chord_start_mbeat`: local chord-entry start.
- `chord_duration_mbeats`: local chord-entry duration.
- `frame_mbeats`: frame step.
- `absolute_chord_start_mbeat`: global/sample timeline anchor.

## Machine Notes

- `RootNote`: one root note, pressure baseline fixed to `0`; pressure comes
  from `lfo_pressure` modulation.
- `DynamicVoicing`: inversion-transition lifecycles with per-note
  `duration_mbeats` carried in `NotePlanItem`.
