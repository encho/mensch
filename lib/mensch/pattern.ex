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

  @doc "Renames the pattern."
  @spec rename(t(), String.t()) :: t()
  def rename(%__MODULE__{} = pattern, name), do: %{pattern | name: name}

  @doc "Renames the track with the given id."
  @spec rename_track(t(), pos_integer(), String.t()) :: t()
  def rename_track(%__MODULE__{} = pattern, track_id, name) do
    update_track(pattern, track_id, &Track.rename(&1, name))
  end

  @doc "Applies a Program Mode tap at `step` on `track_id`."
  @spec apply_program_tap(t(), pos_integer(), pos_integer(), Trig.trig_type()) :: t()
  def apply_program_tap(%__MODULE__{} = pattern, track_id, step, selected_type) do
    update_track(pattern, track_id, &Track.apply_program_tap(&1, step, selected_type))
  end

  @doc "Locks `key` within `namespace` on the trig at `step` on `track_id`."
  @spec lock_param(t(), pos_integer(), pos_integer(), Trig.lock_namespace(), atom()) :: t()
  def lock_param(%__MODULE__{} = pattern, track_id, step, namespace, key) do
    update_track(pattern, track_id, &Track.lock_param(&1, step, namespace, key))
  end

  @doc "Clears the lock for `key` within `namespace` on the trig at `step` on `track_id`."
  @spec clear_lock(t(), pos_integer(), pos_integer(), Trig.lock_namespace(), atom()) :: t()
  def clear_lock(%__MODULE__{} = pattern, track_id, step, namespace, key) do
    update_track(pattern, track_id, &Track.clear_lock(&1, step, namespace, key))
  end

  @doc "Nudges the locked value for `key` within `namespace` on the trig at `step` on `track_id`."
  @spec adjust_lock(t(), pos_integer(), pos_integer(), Trig.lock_namespace(), atom(), :up | :down) ::
          t()
  def adjust_lock(%__MODULE__{} = pattern, track_id, step, namespace, key, direction) do
    update_track(pattern, track_id, &Track.adjust_lock(&1, step, namespace, key, direction))
  end

  @doc "Sets the active track for this pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{} = pattern, track_id) do
    %{pattern | active_track_id: track_id}
  end

  @doc "Toggles the active track's Harmonic Context between Scale and Chromatic mode."
  @spec toggle_track_harmonic_mode(t()) :: t()
  def toggle_track_harmonic_mode(%__MODULE__{active_track_id: track_id} = pattern) do
    update_track(pattern, track_id, &Track.toggle_harmonic_mode/1)
  end

  @doc "Nudges a Track default (not a Trig lock) up or down on the active track."
  @spec adjust_track_default(t(), Trig.lock_namespace(), atom(), :up | :down) :: t()
  def adjust_track_default(
        %__MODULE__{active_track_id: track_id} = pattern,
        namespace,
        key,
        direction
      ) do
    update_track(pattern, track_id, &Track.adjust_default(&1, namespace, key, direction))
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
