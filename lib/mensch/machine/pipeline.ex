defmodule Mensch.Machine.Pipeline do
  @moduledoc """
  Enforced phased machine-render pipeline for first-party machines.

  This behavior formalizes internal architecture phases while keeping the
  external `Mensch.Machine` protocol minimal.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @type render_context :: term()
  @type machine :: struct()

  @callback build_render_context(
              machine(),
              RenderContextCommon.common_fields()
            ) :: render_context()

  @callback build_note_plan(
              machine(),
              ChordSpec.t(),
              render_context()
            ) :: [NotePlanItem.t()]

  @callback render_note_frame_stream(
              NotePlanItem.t(),
              render_context()
            ) :: [map()]

  @callback stitch_note_frame_streams(
              [[map()]],
              render_context()
            ) :: [MachineFrameSequence.frame()]

  @callback assert_invariants([NotePlanItem.t()], render_context()) :: :ok

  @spec build_frame_sequence(
          module(),
          machine(),
          ChordSpec.t(),
          SampleContext.t(),
          TimelineContext.t(),
          keyword()
        ) :: MachineFrameSequence.t()
  def build_frame_sequence(
        module,
        machine,
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      )
      when is_atom(module) and is_list(opts) do
    common_fields = build_common_fields(sample_context, timeline_context, opts)

    render_context =
      module.build_render_context(machine, common_fields)

    note_plan = module.build_note_plan(machine, chord_spec, render_context)

    :ok = module.assert_invariants(note_plan, render_context)

    note_frame_streams =
      Enum.map(note_plan, fn note ->
        module.render_note_frame_stream(note, render_context)
      end)

    %MachineFrameSequence{
      frames: module.stitch_note_frame_streams(note_frame_streams, render_context)
    }
  end

  @spec build_common_fields(SampleContext.t(), TimelineContext.t(), keyword()) ::
          RenderContextCommon.common_fields()
  defp build_common_fields(
         %SampleContext{} = sample_context,
         %TimelineContext{} = timeline_context,
         opts
       )
       when is_list(opts) do
    frame_mbeats = SampleContext.frame_units(sample_context)

    chord_duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    chord_start_mbeat =
      timeline_context
      |> TimelineContext.start_mbeat(sample_context)
      |> snap_mbeats(frame_mbeats)

    RenderContextCommon.common_fields(
      sample_context,
      chord_start_mbeat,
      absolute_chord_start_mbeat(opts),
      frame_mbeats,
      chord_duration_mbeats
    )
  end

  defp snap_mbeats(mbeats, mbeats_per_frame),
    do: round(mbeats / mbeats_per_frame) * mbeats_per_frame

  defp absolute_chord_start_mbeat(opts) do
    case Keyword.get(opts, :absolute_chord_start_mbeat, 0) do
      value when is_integer(value) and value >= 0 -> value
      other -> raise ArgumentError, "invalid :absolute_chord_start_mbeat: #{inspect(other)}"
    end
  end
end
