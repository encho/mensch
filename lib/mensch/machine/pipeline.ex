defmodule Mensch.Machine.Pipeline do
  @moduledoc """
  Enforced phased machine-render pipeline for first-party machines.

  This behavior formalizes internal architecture phases while keeping the
  external `Mensch.Machine` protocol minimal.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Machine.NoteFrame
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

  @callback with_note_modulators(
              NotePlanItem.t(),
              render_context()
            ) :: NotePlanItem.t()

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

    note_plan =
      module.build_note_plan(machine, chord_spec, render_context)
      |> Enum.map(&module.with_note_modulators(&1, render_context))

    :ok = assert_invariants(note_plan, render_context)

    note_frame_streams =
      Enum.map(note_plan, fn note ->
        render_note_frame_stream(note, render_context)
      end)

    %MachineFrameSequence{
      frames: stitch_note_frame_streams(note_frame_streams, render_context)
    }
  end

  @doc "Render a single NotePlanItem at a frame position using attached modulators."
  @spec render_note_to_frame(NotePlanItem.t(), non_neg_integer()) :: NoteFrame.t()
  def render_note_to_frame(%NotePlanItem{} = note, at_mbeat) when is_integer(at_mbeat) do
    local_elapsed_mbeats = at_mbeat - note.start_mbeat

    pressure_modulator = Map.fetch!(note, :pressure_modulator)
    slide_modulator = Map.fetch!(note, :slide_modulator)
    bend_modulator = Map.fetch!(note, :bend_modulator)

    modulated_pressure = pressure_modulator.(at_mbeat, local_elapsed_mbeats)
    modulated_slide = slide_modulator.(at_mbeat, local_elapsed_mbeats)
    modulated_bend = bend_modulator.(at_mbeat, local_elapsed_mbeats)

    NoteFrame.from_note_plan_item(note, %{
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.duration_mbeats,
      pressure: modulated_pressure,
      bend: modulated_bend,
      slide: modulated_slide
    })
  end

  @spec stitch_note_frame_streams([[map()]], render_context()) :: [MachineFrameSequence.frame()]
  defp stitch_note_frame_streams(note_frame_streams, render_context) do
    common = Map.fetch!(render_context, :common)
    chord_start_mbeat = common.chord_start_mbeat
    chord_end_mbeat = chord_start_mbeat + common.chord_duration_mbeats
    frame_mbeats = common.frame_mbeats

    notes_by_mbeat =
      note_frame_streams
      |> List.flatten()
      |> Enum.group_by(& &1.at_mbeat, & &1.note)

    for at_mbeat <- chord_start_mbeat..chord_end_mbeat//frame_mbeats do
      frame_notes =
        notes_by_mbeat
        |> Map.get(at_mbeat, [])
        |> Enum.sort_by(&{Map.get(&1, :note_instance_id, 0), Map.get(&1, :midi_note, 0)})

      %{at_mbeat: at_mbeat, notes: frame_notes}
    end
  end

  @spec assert_invariants([NotePlanItem.t()], render_context()) :: :ok
  defp assert_invariants(note_plan, render_context) do
    common = Map.fetch!(render_context, :common)
    chord_end_mbeat = common.chord_start_mbeat + common.chord_duration_mbeats

    max_note_end_mbeats =
      case note_plan do
        [] -> chord_end_mbeat
        _ -> note_plan |> Enum.map(&(&1.start_mbeat + &1.duration_mbeats)) |> Enum.max()
      end

    if max_note_end_mbeats == chord_end_mbeat do
      :ok
    else
      raise ArgumentError,
            "pipeline invariant violated: last note ends at #{max_note_end_mbeats}, expected #{chord_end_mbeat}"
    end
  end

  @spec render_note_frame_stream(NotePlanItem.t(), render_context()) :: [map()]
  defp render_note_frame_stream(note, render_context) do
    common = Map.fetch!(render_context, :common)
    chord_end_mbeat = common.chord_start_mbeat + common.chord_duration_mbeats
    frame_mbeats = common.frame_mbeats
    note_end_mbeat = min(note.start_mbeat + note.duration_mbeats, chord_end_mbeat)

    for at_mbeat <- note.start_mbeat..note_end_mbeat//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        note: render_note_to_frame(note, at_mbeat)
      }
    end
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
