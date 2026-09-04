defmodule Mensch.Pattern do
  @moduledoc """
  A pattern holds multiple tracks.
  """

  alias Mensch.Track

  defstruct [:id, :name, tracks: [], active_track_id: nil]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          tracks: [Track.t()],
          active_track_id: pos_integer() | nil
        }

  @default_track_count 4

  @doc "Builds a pattern with #{@default_track_count} empty tracks."
  @spec new(pos_integer(), String.t(), pos_integer()) :: t()
  def new(id, name, track_count \\ @default_track_count) do
    tracks = for i <- 1..track_count, do: Track.new(i, "Track #{i}")
    %__MODULE__{id: id, name: name, tracks: tracks, active_track_id: List.first(tracks).id}
  end

  @doc "Toggles the trig at `step` on the track identified by `track_id`."
  @spec toggle_trig(t(), pos_integer(), pos_integer()) :: t()
  def toggle_trig(%__MODULE__{tracks: tracks} = pattern, track_id, step) do
    tracks =
      Enum.map(tracks, fn
        %Track{id: ^track_id} = track -> Track.toggle_trig(track, step)
        track -> track
      end)

    %{pattern | tracks: tracks}
  end

  @doc "Sets the active track for this pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{} = pattern, track_id) do
    %{pattern | active_track_id: track_id}
  end
end
