defmodule Mensch.SampleDb do
  @moduledoc """
  Pseudo-database of built-in sample definitions.

  This module stores sample context, timeline defaults, and sample entry
  collections as in-memory Elixir data structures for local development
  and UI selection.
  """

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.PulseRoot
  alias Mensch.Machines.RootModulated
  alias Mensch.Machines.StrummedMpe
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @samples [
    %{
      id: "sample-1",
      name: "Sample 1 · Dm7 G7 Cmaj7",
      sample_context: %SampleContext{bpm: 120, time_signature: {4, 4}, ppq: 96},
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
            duration_ticks: 768
          },
          machine_module: StrummedMpe
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 3, tick: 0},
            duration_ticks: 480
          },
          machine_module: StrummedMpe
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, tick: 0},
            duration_ticks: 384
          },
          machine_module: StrummedMpe
        }
      ]
    },
    %{
      id: "sample-2",
      name: "Sample 2 · Cmaj7 Drone",
      sample_context: %SampleContext{bpm: 80, time_signature: {4, 4}, ppq: 96},
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
            duration_ticks: 1536
          },
          machine_module: StrummedMpe
        }
      ]
    },
    %{
      id: "sample-3",
      name: "Sample 3 · Dm7 G7 Cmaj7 Root",
      sample_context: %SampleContext{bpm: 120, time_signature: {4, 4}, ppq: 96},
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
            duration_ticks: 768
          },
          machine_module: RootModulated
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 3, tick: 0},
            duration_ticks: 480
          },
          machine_module: RootModulated
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, tick: 0},
            duration_ticks: 384
          },
          machine_module: RootModulated
        }
      ]
    },
    %{
      id: "sample-4",
      name: "Sample 4 · Dm7 G7 Cmaj7 Pulse Root",
      sample_context: %SampleContext{bpm: 120, time_signature: {4, 4}, ppq: 96},
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
            duration_ticks: 768
          },
          machine_module: PulseRoot
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 3, tick: 40},
            duration_ticks: 480
          },
          machine_module: PulseRoot
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, tick: 0},
            duration_ticks: 384
          },
          machine_module: PulseRoot
        }
      ]
    }
  ]

  @doc "Returns default context used by sample-1 and ad hoc single-chord rendering."
  @spec default_sample_context() :: SampleContext.t()
  def default_sample_context do
    @samples
    |> Enum.at(0, %{})
    |> Map.fetch!(:sample_context)
  end

  @doc "Returns sample-1 entries."
  @spec default_sample_entries() :: [map()]
  def default_sample_entries do
    @samples
    |> Enum.at(0, %{})
    |> Map.fetch!(:sample_entries)
  end

  @doc "Returns all built-in samples for selection in the UI."
  @spec default_samples() :: [map()]
  def default_samples, do: @samples
end
