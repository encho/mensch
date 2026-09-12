defmodule Mensch.Machine.NotePlanItem do
  @moduledoc """
  Canonical note-plan item used by machine pipelines.

  This struct represents one planned note event before frame rendering. It is
  intended to be stable across machines so sequencing, envelope assignment,
  rendering, and stitching can evolve independently.

  Pipeline role:

  1. Sequencing stage creates `%NotePlanItem{}` values with pitch, ordering,
    and quantized timing fields.
  2. Envelope/articulation stage enriches each item with `adsr`.
  3. Frame rendering stage consumes the enriched item to emit per-frame note
    states (`:pending`, active ADSR phases, and `:ended`).

  Design intent:

  - `event_index` tracks position in the realized playback sequence.
  - `degree_index` tracks harmonic source position.

  Those are intentionally separate so richer sequencers can diverge them.

  Example:

    # Octave walk sequence for a triad: C4, E4, G4, C5, G4
    # event_index:  0, 1, 2, 3, 4
    # degree_index: 0, 1, 2, 0, 2

  Invariants expected from builders:

  - `delay_mbeats` is already quantized to the machine frame grid.
  - `event_index` and `degree_index` are non-negative.
  - `channel` may be `nil` until global channel allocation.
  - `adsr` may be `nil` until envelope assignment.
  """

  alias Mensch.Envelope.ADSR

  @enforce_keys [
    :note_name,
    :octave,
    :note,
    :velocity,
    :machine_id,
    :chord_instance_id,
    :event_index,
    :degree_index,
    :delay_mbeats
  ]
  defstruct [
    :note_name,
    :octave,
    :note,
    :channel,
    :velocity,
    :machine_id,
    :chord_instance_id,
    :event_index,
    :degree_index,
    :delay_mbeats,
    :adsr
  ]

  @typedoc """
  A single planned note in the machine pipeline.

  Field semantics:

  - `note_name`: Human-readable pitch class (for UI/debug contexts).
  - `octave`: Octave register paired with `note_name`.
  - `note`: MIDI note number used for playback/export.
  - `channel`: Output channel; typically assigned later by global allocation.
  - `velocity`: Initial note-on velocity.
  - `machine_id`: Source machine identifier.
  - `chord_instance_id`: Chord occurrence identity in a sequence/performance.
  - `event_index`: Playback sequence position.
  - `degree_index`: Harmonic source position.
  - `delay_mbeats`: Absolute quantized note start time in mbeat units.
  - `adsr`: Envelope assigned in the articulation stage.
  """
  @type t :: %__MODULE__{
          note_name: atom(),
          octave: integer(),
          note: integer(),
          channel: integer() | nil,
          velocity: integer(),
          machine_id: atom(),
          chord_instance_id: non_neg_integer(),
          event_index: non_neg_integer(),
          degree_index: non_neg_integer(),
          delay_mbeats: non_neg_integer(),
          adsr: ADSR.t() | nil
        }

  @doc """
  Builds a `%NotePlanItem{}` from a map, raising if required keys are missing.

  Use this constructor at sequencing boundaries to fail fast when plan shape
  drifts.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Attaches an ADSR envelope to an existing note-plan item.

  This keeps sequencing and articulation as separate stages while preserving the
  same struct identity across the pipeline.
  """
  @spec with_adsr(t(), ADSR.t()) :: t()
  def with_adsr(%__MODULE__{} = note_plan_item, %ADSR{} = adsr) do
    %__MODULE__{note_plan_item | adsr: adsr}
  end
end
