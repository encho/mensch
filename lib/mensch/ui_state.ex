defmodule Mensch.UIState do
  @moduledoc """
  Ephemeral UI-only interaction state (current mode, trig-type selector,
  and which trig is being edited). Kept separate from musical state
  (`Mensch.Trig`, `Mensch.Track`, `Mensch.Pattern`, ...).
  """

  defstruct mode: :program, trig_type: :note, selected_track_id: nil, selected_step: nil

  @type mode :: :program | :edit_trig
  @type trig_type :: :note | :lock

  @type t :: %__MODULE__{
          mode: mode(),
          trig_type: trig_type(),
          selected_track_id: pos_integer() | nil,
          selected_step: pos_integer() | nil
        }

  @doc "Builds the default UI state: Program Mode, Note trig type selected."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the trig-type selector used in Program Mode."
  @spec set_trig_type(t(), trig_type()) :: t()
  def set_trig_type(%__MODULE__{} = ui, trig_type) when trig_type in [:note, :lock] do
    %{ui | trig_type: trig_type}
  end

  @doc "Enters Trig Edit Mode for the given track/step."
  @spec enter_edit(t(), pos_integer(), pos_integer()) :: t()
  def enter_edit(%__MODULE__{} = ui, track_id, step) do
    %{ui | mode: :edit_trig, selected_track_id: track_id, selected_step: step}
  end

  @doc "Returns to Program Mode, clearing the selected trig."
  @spec exit_edit(t()) :: t()
  def exit_edit(%__MODULE__{} = ui) do
    %{ui | mode: :program, selected_track_id: nil, selected_step: nil}
  end
end
