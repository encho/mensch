defmodule Mensch.Project do
  @moduledoc """
  A project represents a song. It has a name, a tempo (BPM), and one or
  more patterns, one of which is the active pattern.
  """

  alias Mensch.Pattern
  alias Mensch.Trig

  defstruct [:id, :name, bpm: 120, patterns: [], active_pattern_id: nil]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          bpm: pos_integer(),
          patterns: [Pattern.t()],
          active_pattern_id: pos_integer() | nil
        }

  @doc "Builds a project with a single default pattern."
  @spec new(pos_integer(), String.t(), pos_integer()) :: t()
  def new(id, name, bpm \\ 120) do
    pattern = Pattern.new(1, "Pattern 1")
    %__MODULE__{id: id, name: name, bpm: bpm, patterns: [pattern], active_pattern_id: pattern.id}
  end

  @doc "Returns the active pattern for this project."
  @spec active_pattern(t()) :: Pattern.t() | nil
  def active_pattern(%__MODULE__{patterns: patterns, active_pattern_id: id}) do
    Enum.find(patterns, &(&1.id == id))
  end

  @doc "Applies a Program Mode tap at `step` on `track_id`, within the active pattern."
  @spec apply_program_tap(t(), pos_integer(), pos_integer(), atom()) :: t()
  def apply_program_tap(%__MODULE__{} = project, track_id, step, selected_type) do
    update_active_pattern(project, &Pattern.apply_program_tap(&1, track_id, step, selected_type))
  end

  @doc "Locks `key` within `namespace` on the trig at `step` on `track_id`, within the active pattern."
  @spec lock_param(t(), pos_integer(), pos_integer(), Trig.lock_namespace(), atom()) :: t()
  def lock_param(%__MODULE__{} = project, track_id, step, namespace, key) do
    update_active_pattern(project, &Pattern.lock_param(&1, track_id, step, namespace, key))
  end

  @doc "Clears the lock for `key` within `namespace` on the trig at `step` on `track_id`, within the active pattern."
  @spec clear_lock(t(), pos_integer(), pos_integer(), Trig.lock_namespace(), atom()) :: t()
  def clear_lock(%__MODULE__{} = project, track_id, step, namespace, key) do
    update_active_pattern(project, &Pattern.clear_lock(&1, track_id, step, namespace, key))
  end

  @doc "Nudges a locked value, within the active pattern."
  @spec adjust_lock(t(), pos_integer(), pos_integer(), Trig.lock_namespace(), atom(), :up | :down) ::
          t()
  def adjust_lock(%__MODULE__{} = project, track_id, step, namespace, key, direction) do
    update_active_pattern(
      project,
      &Pattern.adjust_lock(&1, track_id, step, namespace, key, direction)
    )
  end

  @doc "Sets the active track on the active pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{} = project, track_id) do
    update_active_pattern(project, &Pattern.set_active_track(&1, track_id))
  end

  @doc "Toggles the active track's Harmonic Context mode, within the active pattern."
  @spec toggle_track_harmonic_mode(t()) :: t()
  def toggle_track_harmonic_mode(%__MODULE__{} = project) do
    update_active_pattern(project, &Pattern.toggle_track_harmonic_mode/1)
  end

  @doc "Nudges a Track default on the active track, within the active pattern."
  @spec adjust_track_default(t(), Trig.lock_namespace(), atom(), :up | :down) :: t()
  def adjust_track_default(%__MODULE__{} = project, namespace, key, direction) do
    update_active_pattern(project, &Pattern.adjust_track_default(&1, namespace, key, direction))
  end

  defp update_active_pattern(
         %__MODULE__{patterns: patterns, active_pattern_id: active_id} = project,
         fun
       ) do
    patterns =
      Enum.map(patterns, fn
        %Pattern{id: ^active_id} = pattern -> fun.(pattern)
        pattern -> pattern
      end)

    %{project | patterns: patterns}
  end
end
