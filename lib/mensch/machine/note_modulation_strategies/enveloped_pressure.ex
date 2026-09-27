defmodule Mensch.Machine.NoteModulationStrategies.EnvelopedPressure do
  @moduledoc """
  Shared note-modulation strategy that combines:

  - a note-anchored pressure envelope
  - an additive sample-anchored pressure curve
  - neutral slide and bend lanes
  """

  alias Mensch.Machine.NoteModulationStrategy
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Modulation
  alias Mensch.Modulation.Lfo
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoEnvelope
  alias Mensch.Modulation.LfoGroup

  @behaviour NoteModulationStrategy

  @type t :: %__MODULE__{
          pressure_attack_mbeats: float(),
          pressure_decay_mbeats: float(),
          pressure_release_mbeats: float(),
          pressure_sustain_level: float(),
          pressure_curve: :sine | :triangle | :square,
          pressure_curve_min: float(),
          pressure_curve_max: float(),
          pressure_curve_cycles_per_bar: float(),
          pressure_curve_shift_mbeats: float(),
          pressure_curve_anchor: :sample | :chord | :note,
          pressure_mode: :add | :multiply,
          error_prefix: String.t()
        }

  defstruct pressure_attack_mbeats: 120.0,
            pressure_decay_mbeats: 280.0,
            pressure_release_mbeats: 120.0,
            pressure_sustain_level: 0.68,
            pressure_curve: :sine,
            pressure_curve_min: 0.0,
            pressure_curve_max: 0.0,
            pressure_curve_cycles_per_bar: 10.0,
            pressure_curve_shift_mbeats: 0.0,
            pressure_curve_anchor: :sample,
            pressure_mode: :add,
            error_prefix: "note_modulation"

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @impl NoteModulationStrategy
  def build_context(%__MODULE__{} = strategy, _note_plan, render_context) do
    common = Map.fetch!(render_context, :common)

    %{
      sample_context: common.sample_context,
      absolute_chord_start_mbeat: common.absolute_chord_start_mbeat,
      slide_lane: slide_lane(strategy),
      bend_lane: bend_lane(strategy)
    }
  end

  @impl NoteModulationStrategy
  def with_note_modulators(
        %__MODULE__{} = strategy,
        %NotePlanItem{} = note,
        modulation_context,
        _render_context
      ) do
    pressure_lane = pressure_lane(note, strategy)
    slide_lane = modulation_context.slide_lane
    bend_lane = modulation_context.bend_lane
    sample_context = modulation_context.sample_context
    absolute_chord_start_mbeat = modulation_context.absolute_chord_start_mbeat

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
          |> clamp_7bit()

        Modulation.apply_to_pressure(0, pressure_value, :add)
      end,
      slide_modulator: fn at_mbeat, local_elapsed_mbeats ->
        slide_modulation =
          evaluate_lane_modulation(
            slide_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        clamp_7bit(slide_modulation)
      end,
      bend_modulator: fn at_mbeat, local_elapsed_mbeats ->
        bend_modulation =
          evaluate_lane_modulation(
            bend_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        apply_to_bend(0.0, bend_modulation, bend_lane.mode)
      end
    })
  end

  defp pressure_lane(%NotePlanItem{} = note, %__MODULE__{} = strategy) do
    attack_mbeats = strategy.pressure_attack_mbeats
    decay_mbeats = strategy.pressure_decay_mbeats
    release_mbeats = strategy.pressure_release_mbeats
    sustain_level = strategy.pressure_sustain_level
    note_duration = note.duration_mbeats * 1.0
    total_requested = attack_mbeats + decay_mbeats + release_mbeats

    if total_requested > note_duration do
      raise ArgumentError,
            "#{strategy.error_prefix} pressure envelope exceeds note duration: attack(#{attack_mbeats}) + decay(#{decay_mbeats}) + release(#{release_mbeats}) = #{total_requested} > note duration #{note_duration} for note_instance_id #{note.note_instance_id}"
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
               curve: strategy.pressure_curve,
               min_value: strategy.pressure_curve_min,
               max_value: strategy.pressure_curve_max,
               cycles_per_bar: strategy.pressure_curve_cycles_per_bar,
               shift_mbeats: strategy.pressure_curve_shift_mbeats,
               anchor: strategy.pressure_curve_anchor
             }}
          ]
        },
        mode: strategy.pressure_mode
      },
      "#{strategy.error_prefix} internal pressure lane"
    )
  end

  defp slide_lane(%__MODULE__{} = strategy) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{
          initial: %LfoCurve{
            curve: :sine,
            min_value: 0.0,
            max_value: 100,
            cycles_per_bar: 1,
            shift_mbeats: 0.0,
            anchor: :note
          },
          operations: []
        },
        mode: :add
      },
      "#{strategy.error_prefix} internal slide lane"
    )
  end

  defp bend_lane(%__MODULE__{} = strategy) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{initial: %LfoCurve{min_value: 0.0, max_value: 0.0}, operations: []},
        mode: :add
      },
      "#{strategy.error_prefix} internal bend lane"
    )
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

  defp apply_to_bend(baseline_bend, modulation_value, :add) do
    clamp_bend(baseline_bend + modulation_value)
  end

  defp apply_to_bend(baseline_bend, modulation_value, :multiply) do
    clamp_bend(baseline_bend * (1 + modulation_value))
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
  defp clamp_bend(value), do: value |> max(-1.0) |> min(1.0)
end
