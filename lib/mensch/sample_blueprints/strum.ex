defmodule Mensch.SampleBlueprints.Strum do
  @moduledoc false

  @behaviour Mensch.SampleBlueprints.Blueprint

  alias Mensch.Machines.Strum
  alias Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure
  alias Mensch.Machines.StrumParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @impl true
  def id, do: "progression__steady_strum__strum1"

  @impl true
  def label, do: "Steady Strum (v1)"

  @impl true
  def additional_param_schema do
    [
      %{
        name: "velocity",
        label: "Velocity",
        type: :int,
        default: 100,
        min: 1,
        max: 127
      },
      %{
        name: "pressure_attack_mbeats",
        label: "Pressure Attack (mbeats)",
        type: :float,
        default: 120.0,
        min: 0.0,
        max: 4000.0,
        step: 1.0
      },
      %{
        name: "pressure_curve",
        label: "Pressure Curve",
        type: :enum,
        default: "sine",
        options: [
          %{value: "sine", label: "Sine"},
          %{value: "triangle", label: "Triangle"},
          %{value: "square", label: "Square"}
        ]
      }
    ]
  end

  @impl true
  def default_additional_params do
    additional_param_schema()
    |> Enum.into(%{}, fn field -> {field.name, field.default} end)
  end

  @impl true
  def build_sample_entries(%{
        chords: chords,
        sample_context: %SampleContext{} = sample_context,
        chord_duration_mbeats: chord_duration_mbeats,
        silence_after_chord_mbeats: silence_after_chord_mbeats,
        additional_params: additional_params
      }) do
    velocity = Map.fetch!(additional_params, "velocity")
    pressure_attack_mbeats = Map.fetch!(additional_params, "pressure_attack_mbeats")
    pressure_curve = Map.fetch!(additional_params, "pressure_curve")

    defaults = StrumParams.default()

    {entries, _cursor} =
      Enum.reduce(chords, {[], 0}, fn chord_spec, {acc, cursor} ->
        machine =
          %Strum{
            params: %StrumParams{
              velocity: velocity,
              modulation_strategy: %StrumEnvelopedPressure{
                defaults.modulation_strategy
                | error_prefix: "strum",
                  pressure_attack_mbeats: pressure_attack_mbeats,
                  pressure_curve: parse_curve!(pressure_curve)
              }
            }
          }

        entry = %{
          chord_spec: chord_spec,
          timeline_context: %TimelineContext{
            start_beat: SampleContext.mbeat_to_position(sample_context, cursor),
            duration_mbeats: chord_duration_mbeats
          },
          machine: machine
        }

        {acc ++ [entry], cursor + chord_duration_mbeats + silence_after_chord_mbeats}
      end)

    {:ok, entries}
  rescue
    error in [KeyError, ArgumentError] -> {:error, Exception.message(error)}
  end

  defp parse_curve!("sine"), do: :sine
  defp parse_curve!("triangle"), do: :triangle
  defp parse_curve!("square"), do: :square

  defp parse_curve!(_),
    do: raise(ArgumentError, "pressure_curve must be one of sine, triangle, square")
end
