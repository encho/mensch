defmodule Mensch.UIState do
  @moduledoc """
  Ephemeral UI/transport state (record/play/func, and which trig is being
  edited). Kept separate from musical state (`Mensch.Trig`, `Mensch.Track`,
  `Mensch.Pattern`, ...).
  """

  defstruct mode: :program,
            recording: false,
            playing: false,
            func_active: false,
            selected_track_id: nil,
            selected_step: nil

  @type mode :: :program | :edit_trig
  @type trig_type :: :note | :lock

  @type t :: %__MODULE__{
          mode: mode(),
          recording: boolean(),
          playing: boolean(),
          func_active: boolean(),
          selected_track_id: pos_integer() | nil,
          selected_step: pos_integer() | nil
        }

  @doc "Builds the default UI state: not recording, not playing, FUNC inactive."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Toggles RECORD on/off."
  @spec toggle_recording(t()) :: t()
  def toggle_recording(%__MODULE__{recording: recording} = ui), do: %{ui | recording: !recording}

  @doc "Toggles PLAY on/off."
  @spec toggle_playing(t()) :: t()
  def toggle_playing(%__MODULE__{playing: playing} = ui), do: %{ui | playing: !playing}

  @doc "Stops playback (sets PLAY inactive). STOP is an action, not a toggle."
  @spec stop_playing(t()) :: t()
  def stop_playing(%__MODULE__{} = ui), do: %{ui | playing: false}

  @doc "Toggles the latched FUNC modifier on/off."
  @spec toggle_func(t()) :: t()
  def toggle_func(%__MODULE__{func_active: func_active} = ui), do: %{ui | func_active: !func_active}

  @doc "The trig type a RECORD-mode tap would create, based on FUNC state."
  @spec trig_type(t()) :: trig_type()
  def trig_type(%__MODULE__{func_active: true}), do: :lock
  def trig_type(%__MODULE__{func_active: false}), do: :note

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

