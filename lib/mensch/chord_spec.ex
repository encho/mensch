defmodule Mensch.ChordSpec do
  @moduledoc """
  Generic chord intent, independent from any concrete machine.

  A chord is defined by:

    * `root` pitch class (`:c`, `:d_sharp`, ...)
    * `modifier` quality recipe (`:maj7`, `:min7`, ...)
    * `octave` root anchor (human-friendly keyboard register)
    * `inversion` signed integer voicing rotation

  `to_midi_notes/1` expands this musical intent into concrete MIDI
  note numbers, with inversion applied.
  """

  @type root ::
          :c
          | :c_sharp
          | :d
          | :d_sharp
          | :e
          | :f
          | :f_sharp
          | :g
          | :g_sharp
          | :a
          | :a_sharp
          | :b

  @type modifier :: :maj | :min | :maj7 | :min7 | :dom7 | :sus2 | :sus4

  @type t :: %__MODULE__{
          root: root(),
          modifier: modifier(),
          octave: integer(),
          inversion: integer()
        }

  @enforce_keys [:root, :modifier, :octave, :inversion]
  defstruct [:root, :modifier, :octave, :inversion]

  @note_names ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a
  @quality_intervals %{
    maj: [0, 4, 7],
    min: [0, 3, 7],
    maj7: [0, 4, 7, 11],
    min7: [0, 3, 7, 10],
    dom7: [0, 4, 7, 10],
    sus2: [0, 2, 7],
    sus4: [0, 5, 7]
  }

  @doc "Builds and validates a chord spec from a map."
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    spec = struct(__MODULE__, attrs)

    case validate(spec) do
      :ok -> {:ok, spec}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Builds and validates a chord spec from a map, raising on invalid data."
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, spec} -> spec
      {:error, reason} -> raise ArgumentError, "invalid chord spec: #{inspect(reason)}"
    end
  end

  @doc "Validates a chord spec."
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = spec) do
    cond do
      not Enum.member?(@note_names, spec.root) ->
        {:error, {:invalid_root, spec.root}}

      not Map.has_key?(@quality_intervals, spec.modifier) ->
        {:error, {:invalid_modifier, spec.modifier}}

      not is_integer(spec.octave) ->
        {:error, {:invalid_octave, spec.octave}}

      not is_integer(spec.inversion) ->
        {:error, {:invalid_inversion, spec.inversion}}

      true ->
        :ok
    end
  end

  @doc "Resolves a chord spec to concrete MIDI note numbers (ascending)."
  @spec to_midi_notes(t()) :: [non_neg_integer()]
  def to_midi_notes(%__MODULE__{} = spec) do
    root_midi = midi_note_number(spec.root, spec.octave)

    @quality_intervals
    |> Map.fetch!(spec.modifier)
    |> Enum.map(&(root_midi + &1))
    |> apply_inversion(spec.inversion)
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {root(), integer()}
  def note_name(note_number) when is_integer(note_number) do
    octave = div(note_number, 12) - 1
    semitone = rem(note_number, 12)
    {Enum.at(@note_names, semitone), octave}
  end

  defp midi_note_number(note, octave) do
    semitone = Enum.find_index(@note_names, &(&1 == note))
    (octave + 1) * 12 + semitone
  end

  defp apply_inversion(notes, inversion) when inversion > 0 do
    1..inversion
    |> Enum.reduce(Enum.sort(notes), fn _, acc ->
      [lowest | rest] = acc
      Enum.sort(rest ++ [lowest + 12])
    end)
  end

  defp apply_inversion(notes, inversion) when inversion < 0 do
    1..abs(inversion)
    |> Enum.reduce(Enum.sort(notes), fn _, acc ->
      highest = List.last(acc)
      front = Enum.drop(acc, -1)
      Enum.sort([highest - 12 | front])
    end)
  end

  defp apply_inversion(notes, _inversion), do: Enum.sort(notes)
end
