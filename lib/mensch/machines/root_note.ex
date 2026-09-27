defmodule Mensch.Machines.RootNote do
  @moduledoc """
  Machine that plays only the harmonic root note for the full entry duration.

  The generated pitch is based on chord identity (`root` + `octave`) and is
  intentionally independent from chord inversion. `octave_offset` transposes the
  root by whole octaves.

  RootNote always uses a zero pressure baseline. Any non-zero pressure must come
  from internal pressure lane modulation.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.Machines.RootNoteParams
  alias Mensch.Modulation
  alias Mensch.Modulation.Lfo
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoEnvelope
  alias Mensch.Modulation.LfoGroup

  defmodule RenderContext do
    @moduledoc false

    alias Mensch.Machine.RenderContextCommon
    alias Mensch.Machines.RootNoteParams

    @enforce_keys [:params, :common]
    defstruct [:params, :common]

    @type t :: %__MODULE__{
            params: RootNoteParams.t(),
            common: RenderContextCommon.t()
          }
  end

  @type t :: %__MODULE__{params: RootNoteParams.t()}

  @behaviour Pipeline

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :root_note

  def params_module, do: RootNoteParams

  def default_params, do: RootNoteParams.default()

  @spec new(RootNoteParams.t()) :: t()
  def new(%RootNoteParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()

    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure
    }
  end

  @impl Pipeline
  @spec build_render_context(t(), RenderContextCommon.common_fields()) ::
          RenderContext.t()
  def build_render_context(
        %__MODULE__{params: params},
        %RenderContextCommon{} = common
      ) do
    struct!(RenderContext, %{params: params, common: common})
  end

  @impl Pipeline
  @spec build_note_plan(t(), ChordSpec.t(), RenderContext.t()) :: [NotePlanItem.t()]
  def build_note_plan(%__MODULE__{}, %ChordSpec{} = chord_spec, %RenderContext{} = render_context) do
    root_midi_note = root_midi_note!(chord_spec, render_context.params.octave_offset)

    {note_name, octave} = ChordSpec.note_name(root_midi_note)

    [
      NotePlanItem.new(%{
        note_name: note_name,
        octave: octave,
        midi_note: root_midi_note,
        channel: nil,
        note_on_velocity: render_context.params.velocity,
        machine_id: id(),
        chord_instance_id: 0,
        note_instance_id: 0,
        degree_index: 0,
        harmonic_tags: [:root],
        role_tags: [],
        machine_note_tags: [],
        start_mbeat: render_context.common.chord_start_mbeat,
        duration_mbeats: render_context.common.chord_duration_mbeats
      })
    ]
  end

  @impl Pipeline
  @spec with_note_modulators(NotePlanItem.t(), RenderContext.t()) :: NotePlanItem.t()
  def with_note_modulators(%NotePlanItem{} = note, %RenderContext{} = render_context) do
    pressure_lane = pressure_lane(note, render_context)
    slide_lane = slide_lane(note, render_context)
    bend_lane = bend_lane(note, render_context)
    sample_context = render_context.common.sample_context
    absolute_chord_start_mbeat = render_context.common.absolute_chord_start_mbeat

    NotePlanItem.with_modulators(note, %{
      pressure_modulator: fn at_mbeat, local_elapsed_mbeats ->
        pressure_value =
          evaluate_lane_modulation(
            pressure_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        Modulation.apply_to_pressure(0, pressure_value, pressure_lane.mode)
      end,
      slide_modulator: fn at_mbeat, local_elapsed_mbeats ->
        slide_value =
          evaluate_lane_modulation(
            slide_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        apply_to_7bit(0, slide_value, slide_lane.mode)
      end,
      bend_modulator: fn at_mbeat, local_elapsed_mbeats ->
        bend_value =
          evaluate_lane_modulation(
            bend_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        apply_to_bend(0.0, bend_value, bend_lane.mode)
      end
    })
  end

  @doc false
  @spec normalize_params(RootNoteParams.t()) :: RootNoteParams.t()
  def normalize_params(%RootNoteParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> then(&struct!(RootNoteParams, &1))
  end

  defp evaluate_lane_modulation(
         %{lfo: lfo},
         at_mbeat,
         sample_context,
         absolute_chord_start_mbeat,
         local_elapsed_mbeats
       ) do
    Lfo.evaluate(
      lfo,
      at_mbeat,
      sample_context,
      absolute_chord_start_mbeat,
      local_elapsed_mbeats
    )
  end

  defp pressure_lane(%NotePlanItem{} = note, %RenderContext{}) do
    attack_mbeats = 120.0
    decay_mbeats = 280.0
    release_mbeats = 120.0
    sustain_level = 0.68
    note_duration = note.duration_mbeats * 1.0
    total_requested = attack_mbeats + decay_mbeats + release_mbeats

    if total_requested > note_duration do
      raise ArgumentError,
            "root_note pressure envelope exceeds note duration: attack(#{attack_mbeats}) + decay(#{decay_mbeats}) + release(#{release_mbeats}) = #{total_requested} > note duration #{note_duration} for note_instance_id #{note.note_instance_id}"
    end

    hold_mbeats = note_duration - total_requested

    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{
          initial: %LfoEnvelope{
            start_value: 0.0,
            peak_value: 127.0,
            sustain_value: sustain_level * 127.0,
            end_value: 0.0,
            attack_mbeats: attack_mbeats,
            decay_mbeats: decay_mbeats,
            hold_mbeats: hold_mbeats,
            release_mbeats: release_mbeats,
            interpolation_function: :linear,
            shift_mbeats: 0.0,
            anchor: :note
          },
          operations: [
            {:add,
             %LfoCurve{
               curve: :sine,
               min_value: 0,
               max_value: 0,
               cycles_per_bar: 10.0,
               shift_mbeats: 0.0,
               anchor: :sample
             }}
          ]
        },
        mode: :add
      },
      "root_note internal pressure lane"
    )
  end

  defp slide_lane(%NotePlanItem{}, %RenderContext{}) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{initial: %LfoCurve{min_value: 0.0, max_value: 0.0}, operations: []},
        mode: :add
      },
      "root_note internal slide lane"
    )
  end

  defp bend_lane(%NotePlanItem{}, %RenderContext{}) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{initial: %LfoCurve{min_value: 0.0, max_value: 0.0}, operations: []},
        mode: :add
      },
      "root_note internal bend lane"
    )
  end

  defp apply_to_7bit(baseline_7bit, modulation_value, :add) do
    normalized = baseline_7bit / 127 + modulation_value
    clamp_7bit(normalized * 127)
  end

  defp apply_to_7bit(baseline_7bit, modulation_value, :multiply) do
    normalized = baseline_7bit / 127 * (1 + modulation_value)
    clamp_7bit(normalized * 127)
  end

  defp apply_to_bend(baseline_bend, modulation_value, :add) do
    clamp_bend(baseline_bend + modulation_value)
  end

  defp apply_to_bend(baseline_bend, modulation_value, :multiply) do
    clamp_bend(baseline_bend * (1 + modulation_value))
  end

  defp root_midi_note!(%ChordSpec{} = chord_spec, octave_offset) when is_integer(octave_offset) do
    midi_note = midi_note_number(chord_spec.root, chord_spec.octave) + octave_offset * 12

    if midi_note < 0 or midi_note > 127 do
      raise ArgumentError,
            "root_note produced out-of-range midi note #{midi_note} from root #{inspect(chord_spec.root)} octave #{inspect(chord_spec.octave)} with octave_offset #{inspect(octave_offset)}"
    end

    midi_note
  end

  defp midi_note_number(note, octave) do
    semitone =
      case note do
        :c -> 0
        :c_sharp -> 1
        :d -> 2
        :d_sharp -> 3
        :e -> 4
        :f -> 5
        :f_sharp -> 6
        :g -> 7
        :g_sharp -> 8
        :a -> 9
        :a_sharp -> 10
        :b -> 11
      end

    (octave + 1) * 12 + semitone
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
  defp clamp_bend(value), do: value |> max(-1.0) |> min(1.0)
end

defimpl Mensch.Machine, for: Mensch.Machines.RootNote do
  alias Mensch.Machines.RootNote

  def id(_machine), do: RootNote.id()

  def controls(%RootNote{params: params}) do
    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure
    }
  end

  def build_frame_sequence(
        %RootNote{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    normalized_params = RootNote.normalize_params(params)

    Mensch.Machine.Pipeline.build_frame_sequence(
      RootNote,
      %RootNote{params: normalized_params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
  end
end
