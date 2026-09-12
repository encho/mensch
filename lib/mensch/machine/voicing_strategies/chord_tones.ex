defmodule Mensch.Machine.VoicingStrategies.ChordTones do
  @moduledoc """
  Baseline voicing strategy that emits chord tones in their default order.
  """

  @behaviour Mensch.Machine.VoicingStrategy

  alias Mensch.ChordSpec

  @type t :: %__MODULE__{}

  defstruct []

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @impl true
  @spec build_voiced_notes(t(), ChordSpec.t()) :: [Mensch.Machine.VoicingStrategy.voiced_note()]
  def build_voiced_notes(%__MODULE__{}, %ChordSpec{} = chord_spec) do
    chord_spec
    |> ChordSpec.to_midi_notes()
    |> Enum.with_index()
    |> Enum.map(fn {note_number, index} ->
      %{note: note_number, degree_index: index, event_index: index}
    end)
  end
end
