defmodule Mensch.Machine.NoteFrame do
  @moduledoc """
  Canonical per-frame note event shape emitted by machines.

  A note frame represents one note's runtime state at a specific frame point,
  including articulation phase and outbound MPE controls.
  """

  alias Mensch.Machine.NotePlanItem

  @enforce_keys [
    :note_name,
    :octave,
    :midi_note,
    :channel,
    :velocity,
    :machine_id,
    :chord_instance_id,
    :event_index,
    :phase,
    :note_on,
    :note_off,
    :pressure,
    :bend,
    :slide
  ]
  defstruct [
    :note_name,
    :octave,
    :midi_note,
    :channel,
    :velocity,
    :machine_id,
    :chord_instance_id,
    :event_index,
    :degree_index,
    :sample_entry_index,
    :phase,
    :note_on,
    :note_off,
    :pressure,
    :bend,
    :slide
  ]

  @type t :: %__MODULE__{
          note_name: atom(),
          octave: integer(),
          midi_note: non_neg_integer(),
          channel: non_neg_integer() | nil,
          velocity: non_neg_integer(),
          machine_id: atom(),
          chord_instance_id: non_neg_integer(),
          event_index: non_neg_integer(),
          degree_index: non_neg_integer() | nil,
          sample_entry_index: integer() | nil,
          phase: atom(),
          note_on: boolean(),
          note_off: boolean(),
          pressure: non_neg_integer(),
          bend: float(),
          slide: non_neg_integer()
        }

  @doc "Builds a note frame from a map with matching fields."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)

  @doc """
  Builds a note frame by copying base pitch/provenance fields from a
  `%NotePlanItem{}` and merging runtime frame fields from `attrs`.
  """
  @spec from_note_plan_item(NotePlanItem.t(), map()) :: t()
  def from_note_plan_item(%NotePlanItem{} = note_plan_item, attrs) when is_map(attrs) do
    base = %{
      note_name: note_plan_item.note_name,
      octave: note_plan_item.octave,
      midi_note: note_plan_item.midi_note,
      channel: note_plan_item.channel,
      velocity: note_plan_item.velocity,
      machine_id: note_plan_item.machine_id,
      chord_instance_id: note_plan_item.chord_instance_id,
      event_index: note_plan_item.event_index,
      degree_index: note_plan_item.degree_index,
      sample_entry_index: nil
    }

    new(Map.merge(base, attrs))
  end

  @doc """
  Builds a note frame by copying shared base fields from a source note map
  and merging runtime frame fields from `attrs`.
  """
  @spec from_note_source(map(), map()) :: t()
  def from_note_source(note, attrs) when is_map(note) and is_map(attrs) do
    note_plan_item =
      NotePlanItem.new(%{
        note_name: Map.fetch!(note, :note_name),
        octave: Map.fetch!(note, :octave),
        midi_note: Map.fetch!(note, :midi_note),
        channel: Map.fetch!(note, :channel),
        velocity: Map.fetch!(note, :velocity),
        machine_id: Map.fetch!(note, :machine_id),
        chord_instance_id: Map.fetch!(note, :chord_instance_id),
        event_index: Map.fetch!(note, :event_index),
        degree_index: Map.get(note, :degree_index, 0),
        delay_mbeats: Map.fetch!(note, :delay_mbeats)
      })

    attrs =
      attrs
      |> Map.put_new(:sample_entry_index, Map.get(note, :sample_entry_index))

    from_note_plan_item(note_plan_item, attrs)
  end
end
