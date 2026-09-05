defmodule Mensch.Performance.Engine do
  @moduledoc """
  Takes a complete `Mensch.Project` and generates its ordered
  performance timeline: resolve each chord in the progression, run it
  through the project's machine, and collect the resulting events.

  Deterministic and pure — no processes, no real-time scheduling.
  """

  alias Mensch.Harmony.Resolver
  alias Mensch.Machine.RootNote
  alias Mensch.Machine.RootNoteMpe
  alias Mensch.Performance.Event
  alias Mensch.Project

  @doc """
  Generates the ordered list of performance events for `project`.

      iex> Mensch.Performance.Engine.generate(Mensch.Project.default())
      [
        %Mensch.Performance.Event{type: :note_on, at_beat: 0.0, note: {:d, 3}, velocity: 90},
        %Mensch.Performance.Event{type: :note_off, at_beat: 4.0, note: {:d, 3}, velocity: nil},
        %Mensch.Performance.Event{type: :note_on, at_beat: 4.0, note: {:g, 3}, velocity: 90},
        %Mensch.Performance.Event{type: :note_off, at_beat: 8.0, note: {:g, 3}, velocity: nil},
        %Mensch.Performance.Event{type: :note_on, at_beat: 8.0, note: {:c, 3}, velocity: 90},
        %Mensch.Performance.Event{type: :note_off, at_beat: 12.0, note: {:c, 3}, velocity: nil}
      ]

  """
  @spec generate(Project.t()) :: [Event.t()]
  def generate(%Project{
        key: key,
        chord_duration: {:beats, duration},
        progression: progression,
        machine: machine
      }) do
    machine_module = machine_module(machine)
    duration = duration * 1.0

    progression
    |> Enum.with_index()
    |> Enum.flat_map(fn {chord_spec, index} ->
      resolved_chord = Resolver.resolve(key, chord_spec)
      start_beat = index * duration
      context = %{start_beat: start_beat, duration_beats: duration}

      machine_module.generate(resolved_chord, machine, context)
    end)
    |> Enum.sort_by(& &1.at_beat)
  end

  defp machine_module(%RootNote{}), do: RootNote
  defp machine_module(%RootNoteMpe{}), do: RootNoteMpe
end
