defmodule Mensch.SampleBlueprints.DynamicVoicing do
  @moduledoc false

  @behaviour Mensch.SampleBlueprints.Blueprint

  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @impl true
  def id, do: "progression__alternating_wander__dv1"

  @impl true
  def label, do: "Alternating Wander (DV v1)"

  @impl true
  def additional_param_schema do
    [
      %{
        name: "direction_mode",
        label: "Direction Mode",
        type: :enum,
        default: "alternate",
        options: [
          %{value: "alternate", label: "Alternate up/down"},
          %{value: "up", label: "Always up"},
          %{value: "down", label: "Always down"}
        ]
      },
      %{
        name: "number_of_inversions",
        label: "Number of Inversions",
        type: :int,
        default: 8,
        min: 1,
        max: 128
      },
      %{
        name: "pressure_attack_mbeats",
        label: "Pressure Attack (mbeats)",
        type: :float,
        default: 50.0,
        min: 0.0,
        max: 4000.0,
        step: 1.0
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
    direction_mode = Map.fetch!(additional_params, "direction_mode")
    number_of_inversions = Map.fetch!(additional_params, "number_of_inversions")
    pressure_attack_mbeats = Map.fetch!(additional_params, "pressure_attack_mbeats")

    defaults = DynamicVoicingParams.default()

    {entries, _cursor} =
      Enum.reduce(Enum.with_index(chords), {[], 0}, fn {chord_spec, index}, {acc, cursor} ->
        chord_spec = put_in(chord_spec.voicing.inversion_resolution_mode, :anchor_then_wander)
        direction = direction_for(direction_mode, index)

        machine =
          %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: direction,
              number_of_inversions: number_of_inversions,
              modulation_strategy: %DynamicVoicingEnvelopedPressure{
                defaults.modulation_strategy
                | error_prefix: "dynamic_voicing",
                  pressure_attack_mbeats: pressure_attack_mbeats
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

  defp direction_for("alternate", index), do: if(rem(index, 2) == 0, do: :up, else: :down)
  defp direction_for("up", _index), do: :up
  defp direction_for("down", _index), do: :down
  defp direction_for(_, index), do: direction_for("alternate", index)
end
