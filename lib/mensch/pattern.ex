defmodule Mensch.Pattern do
  @moduledoc """
  A pattern holds multiple tracks, one of which is the active track.
  """

  alias Mensch.Track
  alias Mensch.Trig

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

  @doc "Returns the track with the given id, or nil if not found."
  @spec track(t(), pos_integer()) :: Track.t() | nil
  def track(%__MODULE__{tracks: tracks}, track_id) do
    Enum.find(tracks, &(&1.id == track_id))
  end

  @doc "Applies a Program Mode tap at `step` on `track_id`."
  @spec apply_program_tap(t(), pos_integer(), pos_integer(), Trig.trig_type()) :: t()
  def apply_program_tap(%__MODULE__{} = pattern, track_id, step, selected_type) do
    update_track(pattern, track_id, &Track.apply_program_tap(&1, step, selected_type))
  end

  @doc "Locks `key` on the trig at `step` on `track_id`."
  @spec lock_param(t(), pos_integer(), pos_integer(), atom()) :: t()
  def lock_param(%__MODULE__{} = pattern, track_id, step, key) do
    update_track(pattern, track_id, &Track.lock_param(&1, step, key))
  end

  @doc "Clears the lock for `key` on the trig at `step` on `track_id`."
  @spec clear_lock(t(), pos_integer(), pos_integer(), atom()) :: t()
  def clear_lock(%__MODULE__{} = pattern, track_id, step, key) do
    update_track(pattern, track_id, &Track.clear_lock(&1, step, key))
  end

  @doc "Nudges the locked value for `key` on the trig at `step` on `track_id`."
  @spec adjust_lock(t(), pos_integer(), pos_integer(), atom(), :up | :down) :: t()
  def adjust_lock(%__MODULE__{} = pattern, track_id, step, key, direction) do
    update_track(pattern, track_id, &Track.adjust_lock(&1, step, key, direction))
  end

  @doc "Sets the active track for this pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{} = pattern, track_id) do
    %{pattern | active_track_id: track_id}
  end

  defp update_track(%__MODULE__{tracks: tracks} = pattern, track_id, fun) do
    tracks =
      Enum.map(tracks, fn
        %Track{id: ^track_id} = track -> fun.(track)
        track -> track
      end)

    %{pattern | tracks: tracks}
  end
end
