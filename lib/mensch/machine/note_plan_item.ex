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

  - `note_instance_id` identifies one note lifecycle from note-on to note-off.
  - `degree_index` tracks harmonic source position.
  - `harmonic_tags`, `role_tags`, and `machine_note_tags` carry semantic
    metadata for downstream modulation/rendering decisions.

  Those are intentionally separate so richer sequencers can diverge them.

  Example:

    # Octave walk sequence for a triad: C4, E4, G4, C5, G4
    # note_instance_id:  0, 1, 2, 3, 4
    # degree_index: 0, 1, 2, 0, 2

  Invariants expected from builders:

  - `start_mbeat` is already quantized to the machine frame grid.
  - `note_instance_id` and `degree_index` are non-negative.
  - `channel` may be `nil` until global channel allocation.
  - `adsr` may be `nil` until envelope assignment.

  Example item (pre-envelope):

      %Mensch.Machine.NotePlanItem{
        note_name: :c,
        octave: 4,
        midi_note: 60,
        channel: nil,
        note_on_velocity: 100,
        machine_id: :simple_chord,
        chord_instance_id: 0,
        note_instance_id: 3,
        degree_index: 0,
        harmonic_tags: [:root],
        role_tags: [],
        machine_note_tags: [],
        start_mbeat: 540,
        adsr: nil
      }
  """

  alias Mensch.Envelope.ADSR

  @harmonic_tags [
    :root,
    :third,
    :fifth,
    :seventh,
    :ninth,
    :eleventh,
    :thirteenth,
    :tension,
    :altered
  ]

  @role_tags [
    :bass,
    :lead,
    :accent,
    :support,
    :pad,
    :ghost
  ]

  @machine_note_tags [
    :entering,
    :sustaining,
    :releasing,
    :strum_head,
    :strum_tail,
    :cycle_boundary
  ]

  @type harmonic_tag ::
          :root
          | :third
          | :fifth
          | :seventh
          | :ninth
          | :eleventh
          | :thirteenth
          | :tension
          | :altered

  @type role_tag :: :bass | :lead | :accent | :support | :pad | :ghost

  @type machine_note_tag ::
          :entering
          | :sustaining
          | :releasing
          | :strum_head
          | :strum_tail
          | :cycle_boundary

  @enforce_keys [
    :note_name,
    :octave,
    :midi_note,
    :note_on_velocity,
    :machine_id,
    :chord_instance_id,
    :note_instance_id,
    :degree_index,
    :harmonic_tags,
    :role_tags,
    :machine_note_tags,
    :start_mbeat
  ]
  defstruct note_name: nil,
            octave: nil,
            midi_note: nil,
            channel: nil,
            note_on_velocity: nil,
            machine_id: nil,
            chord_instance_id: nil,
            note_instance_id: nil,
            degree_index: nil,
            start_mbeat: nil,
            adsr: nil,
            harmonic_tags: [],
            role_tags: [],
            machine_note_tags: []

  @typedoc """
  A single planned note in the machine pipeline.

  Field semantics:

  - `note_name`: Human-readable pitch class (for UI/debug contexts), e.g. `:c`.
  - `octave`: Octave register paired with `note_name`, e.g. `4`.
  - `midi_note`: MIDI note number used for playback/export, e.g. `60`.
  - `channel`: Output channel; typically assigned later by global allocation,
    e.g. `nil` before allocation, then `2`.
  - `note_on_velocity`: Initial note-on velocity, e.g. `100`.
  - `machine_id`: Source machine identifier, e.g. `:simple_chord`.
  - `chord_instance_id`: Chord occurrence identity in a sequence/performance,
    e.g. `0` for the first entry.
  - `note_instance_id`: Stable note lifecycle id, e.g. `3`.
  - `degree_index`: Harmonic source position, e.g. `0` for the root degree.
  - `harmonic_tags`: Harmonic labels for this note, e.g. `[:root]`.
  - `role_tags`: Arrangement role labels, e.g. `[]`.
  - `machine_note_tags`: Machine-local lifecycle/semantic tags,
    e.g. `[:entering]`.
  - `start_mbeat`: Absolute quantized note start time in mbeat units,
    e.g. `540`.
  - `adsr`: Envelope assigned in the articulation stage, e.g. `nil` before
    assignment, then `%Mensch.Envelope.ADSR{...}`.
  """
  @type t :: %__MODULE__{
          note_name: atom(),
          octave: integer(),
          midi_note: integer(),
          channel: integer() | nil,
          note_on_velocity: integer(),
          machine_id: atom(),
          chord_instance_id: non_neg_integer(),
          note_instance_id: non_neg_integer(),
          degree_index: non_neg_integer(),
          harmonic_tags: [harmonic_tag()],
          role_tags: [role_tag()],
          machine_note_tags: [machine_note_tag()],
          start_mbeat: non_neg_integer(),
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
    |> normalize_and_validate_tags!()
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

  defp normalize_and_validate_tags!(%__MODULE__{} = note_plan_item) do
    harmonic_tags = normalize_and_validate_tag_list!(note_plan_item.harmonic_tags, @harmonic_tags)
    role_tags = normalize_and_validate_tag_list!(note_plan_item.role_tags, @role_tags)

    machine_note_tags =
      normalize_and_validate_tag_list!(note_plan_item.machine_note_tags, @machine_note_tags)

    %__MODULE__{
      note_plan_item
      | harmonic_tags: harmonic_tags,
        role_tags: role_tags,
        machine_note_tags: machine_note_tags
    }
  end

  defp normalize_and_validate_tag_list!(tags, allowed_tags) when is_list(tags) do
    tags
    |> Enum.uniq()
    |> Enum.map(fn tag ->
      if is_atom(tag) and Enum.member?(allowed_tags, tag) do
        tag
      else
        raise ArgumentError,
              "invalid tag #{inspect(tag)}; allowed tags: #{inspect(allowed_tags)}"
      end
    end)
  end

  defp normalize_and_validate_tag_list!(other, _allowed_tags) do
    raise ArgumentError, "expected tag list, got: #{inspect(other)}"
  end
end
