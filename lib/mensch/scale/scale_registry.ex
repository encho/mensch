defmodule Mensch.Scale.ScaleRegistry do
  @moduledoc """
  Registry of scale families and standalone scales.
  """

  @major_modes %{
    1 => "Ionian",
    2 => "Dorian",
    3 => "Phrygian",
    4 => "Lydian",
    5 => "Mixolydian",
    6 => "Aeolian",
    7 => "Locrian"
  }

  @harmonic_minor_modes %{
    1 => "Harmonic Minor",
    2 => "Locrian Natural 6",
    3 => "Ionian Augmented",
    4 => "Dorian #4",
    5 => "Phrygian Dominant",
    6 => "Lydian #2",
    7 => "Ultra Locrian"
  }

  @melodic_minor_modes %{
    1 => "Melodic Minor",
    2 => "Dorian b2",
    3 => "Lydian Augmented",
    4 => "Lydian Dominant",
    5 => "Mixolydian b6",
    6 => "Locrian Natural 2",
    7 => "Altered"
  }

  @harmonic_major_modes %{
    1 => "Harmonic Major",
    2 => "Dorian b5",
    3 => "Phrygian b4",
    4 => "Lydian b3",
    5 => "Mixolydian b2",
    6 => "Lydian Augmented #2",
    7 => "Locrian bb7"
  }

  @families [
    %{
      id: :major,
      name: "Major",
      intervals: [0, 2, 4, 5, 7, 9, 11],
      mode_names: @major_modes,
      aliases: ["Ionian Family"]
    },
    %{
      id: :harmonic_minor,
      name: "Harmonic Minor",
      intervals: [0, 2, 3, 5, 7, 8, 11],
      mode_names: @harmonic_minor_modes,
      aliases: []
    },
    %{
      id: :melodic_minor,
      name: "Melodic Minor",
      intervals: [0, 2, 3, 5, 7, 9, 11],
      mode_names: @melodic_minor_modes,
      aliases: ["Jazz Melodic Minor"]
    },
    %{
      id: :harmonic_major,
      name: "Harmonic Major",
      intervals: [0, 2, 4, 5, 7, 8, 11],
      mode_names: @harmonic_major_modes,
      aliases: []
    }
  ]

  @standalones [
    %{id: :major_pentatonic, name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9], aliases: []},
    %{id: :minor_pentatonic, name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10], aliases: []},
    %{id: :minor_blues, name: "Minor Blues", intervals: [0, 3, 5, 6, 7, 10], aliases: []},
    %{id: :whole_tone, name: "Whole-Tone", intervals: [0, 2, 4, 6, 8, 10], aliases: []},
    %{
      id: :half_whole_diminished,
      name: "Half-Whole Diminished",
      intervals: [0, 1, 3, 4, 6, 7, 9, 10],
      aliases: []
    },
    %{
      id: :whole_half_diminished,
      name: "Whole-Half Diminished",
      intervals: [0, 2, 3, 5, 6, 8, 9, 11],
      aliases: []
    },
    %{
      id: :double_harmonic_major,
      name: "Double Harmonic Major",
      intervals: [0, 1, 4, 5, 7, 8, 11],
      aliases: []
    }
  ]

  @doc "Returns modal families."
  @spec families() :: [map()]
  def families, do: @families

  @doc "Returns standalone scales with no mode selector requirement."
  @spec standalone_scales() :: [map()]
  def standalone_scales, do: @standalones

  @doc "Returns all scale definitions."
  @spec all() :: [map()]
  def all, do: @families ++ @standalones

  @doc "Finds a scale definition by id."
  @spec fetch(atom()) :: {:ok, map()} | {:error, :unknown_scale_family}
  def fetch(id) when is_atom(id) do
    case Enum.find(all(), &(&1.id == id)) do
      nil -> {:error, :unknown_scale_family}
      entry -> {:ok, entry}
    end
  end
end
