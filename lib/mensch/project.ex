defmodule Mensch.Project do
  @moduledoc """
  A project represents a song. It has a name, a tempo (BPM), and one or
  more patterns, one of which is the active pattern.
  """

  alias Mensch.Pattern

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

  @doc "Toggles the trig at `step` on `track_id`, within the active pattern."
  @spec toggle_trig(t(), pos_integer(), pos_integer()) :: t()
  def toggle_trig(%__MODULE__{patterns: patterns, active_pattern_id: active_id} = project, track_id, step) do
    patterns =
      Enum.map(patterns, fn
        %Pattern{id: ^active_id} = pattern -> Pattern.toggle_trig(pattern, track_id, step)
        pattern -> pattern
      end)

    %{project | patterns: patterns}
  end

  @doc "Sets the active track on the active pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{patterns: patterns, active_pattern_id: active_id} = project, track_id) do
    patterns =
      Enum.map(patterns, fn
        %Pattern{id: ^active_id} = pattern -> Pattern.set_active_track(pattern, track_id)
        pattern -> pattern
      end)

    %{project | patterns: patterns}
  end
end
