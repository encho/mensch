defmodule Mensch.ChordSpec do
  @moduledoc """
  Generic chord intent, independent from any concrete machine.

  A chord is defined by:

    * `root` pitch class (`:c`, `:d_sharp`, `:e_flat`, ...)
    * `tones` explicit chord degrees (`["1", "3", "5", "7"]`, ...)
    * `octave` root anchor (human-friendly keyboard register)
    * `inversion` signed integer voicing rotation for upper chord tones
    * `bass` optional slash bass note (e.g. `:a` for C/A)
    * `function` optional harmonic-function metadata (`"ii"`, `"V/vi"`, ...)
    * `key` optional key metadata (e.g. `%{tonic: :b_flat, mode: :major}`)

  `to_midi_notes/1` expands this musical intent into concrete MIDI
  note numbers, with inversion applied to upper tones. If `bass` is set,
  bass is anchored independently below the upper structure.
  """

  @type pitch_class ::
          :c
          | :c_flat
          | :b_sharp
          | :c_sharp
          | :d_flat
          | :d
          | :d_sharp
          | :e_flat
          | :e
          | :f_flat
          | :e_sharp
          | :f
          | :f_sharp
          | :g_flat
          | :g
          | :g_sharp
          | :a_flat
          | :a
          | :a_sharp
          | :b_flat
          | :b

  @type tone :: String.t()
  @type key_mode :: :major | :minor
  @type quality ::
          :maj
          | :min
          | :maj7
          | :min7
          | :dom7
          | :sus2
          | :sus4
          | :maj9
          | :min9
          | :dom9
          | :maj11
          | :min11
          | :dom13
          | :six_nine
          | :min6
          | :dim
          | :half_dim
          | :dim7
          | :aug
          | :min7_add11

  @type key_spec :: %{
          tonic: pitch_class(),
          mode: key_mode()
        }

  @type t :: %__MODULE__{
          root: pitch_class(),
          tones: [tone()] | nil,
          quality: quality() | nil,
          octave: integer(),
          inversion: integer(),
          bass: pitch_class() | nil,
          function: String.t() | nil,
          key: key_spec() | nil
        }

  @enforce_keys [:root, :octave, :inversion]
  defstruct [:root, :tones, :quality, :octave, :inversion, bass: nil, function: nil, key: nil]

  @sharp_note_names ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a
  @flat_note_names ~w(c d_flat d e_flat e f g_flat g a_flat a b_flat b)a

  @tone_intervals %{
    "1" => 0,
    "b2" => 1,
    "2" => 2,
    "#2" => 3,
    "b3" => 3,
    "3" => 4,
    "4" => 5,
    "#4" => 6,
    "b5" => 6,
    "5" => 7,
    "#5" => 8,
    "b6" => 8,
    "6" => 9,
    "bb7" => 9,
    "b7" => 10,
    "7" => 11,
    "b9" => 13,
    "9" => 14,
    "#9" => 15,
    "11" => 17,
    "#11" => 18,
    "b13" => 20,
    "13" => 21
  }

  @legacy_tones %{
    maj: ["1", "3", "5"],
    min: ["1", "b3", "5"],
    maj7: ["1", "3", "5", "7"],
    min7: ["1", "b3", "5", "b7"],
    dom7: ["1", "3", "5", "b7"],
    sus2: ["1", "2", "5"],
    sus4: ["1", "4", "5"]
  }

  @quality_tones %{
    maj: ["1", "3", "5"],
    min: ["1", "b3", "5"],
    maj7: ["1", "3", "5", "7"],
    min7: ["1", "b3", "5", "b7"],
    dom7: ["1", "3", "5", "b7"],
    sus2: ["1", "2", "5"],
    sus4: ["1", "4", "5"],
    maj9: ["1", "3", "5", "7", "9"],
    min9: ["1", "b3", "5", "b7", "9"],
    dom9: ["1", "3", "5", "b7", "9"],
    maj11: ["1", "3", "5", "7", "9", "11"],
    min11: ["1", "b3", "5", "b7", "9", "11"],
    dom13: ["1", "3", "5", "b7", "9", "13"],
    six_nine: ["1", "3", "5", "6", "9"],
    min6: ["1", "b3", "5", "6"],
    dim: ["1", "b3", "b5"],
    half_dim: ["1", "b3", "b5", "b7"],
    dim7: ["1", "b3", "b5", "bb7"],
    aug: ["1", "3", "#5"],
    min7_add11: ["1", "b3", "5", "b7", "11"]
  }

  @doc "Builds and validates a chord spec from a map."
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    attrs = maybe_expand_legacy_modifier(attrs)
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
      not valid_pitch_class?(spec.root) ->
        {:error, {:invalid_root, spec.root}}

      is_nil(spec.tones) and is_nil(spec.quality) ->
        {:error, {:missing_chord_content, :tones_or_quality_required}}

      not is_nil(spec.quality) and not Map.has_key?(@quality_tones, spec.quality) ->
        {:error, {:invalid_quality, spec.quality}}

      not is_nil(spec.tones) and (not is_list(spec.tones) or spec.tones == []) ->
        {:error, {:invalid_tones, spec.tones}}

      not is_nil(spec.tones) and
          Enum.any?(spec.tones, &(not (is_binary(&1) and Map.has_key?(@tone_intervals, &1)))) ->
        {:error, {:invalid_tones, spec.tones}}

      not is_integer(spec.octave) ->
        {:error, {:invalid_octave, spec.octave}}

      not is_integer(spec.inversion) ->
        {:error, {:invalid_inversion, spec.inversion}}

      not is_nil(spec.bass) and not valid_pitch_class?(spec.bass) ->
        {:error, {:invalid_bass, spec.bass}}

      not is_nil(spec.function) and not is_binary(spec.function) ->
        {:error, {:invalid_function, spec.function}}

      not is_nil(spec.key) and not valid_key_spec?(spec.key) ->
        {:error, {:invalid_key, spec.key}}

      true ->
        :ok
    end
  end

  @doc "Resolves a chord spec to concrete MIDI note numbers (ascending)."
  @spec to_midi_notes(t()) :: [non_neg_integer()]
  def to_midi_notes(%__MODULE__{} = spec) do
    root_midi = midi_note_number(spec.root, spec.octave)

    upper_notes =
      tones(spec)
      |> Enum.uniq()
      |> Enum.map(&(root_midi + Map.fetch!(@tone_intervals, &1)))
      |> Enum.sort()
      |> apply_inversion(spec.inversion)

    case spec.bass do
      nil ->
        upper_notes

      bass ->
        bass_midi = anchored_bass_midi(bass, spec.octave, upper_notes)
        ([bass_midi] ++ upper_notes) |> Enum.uniq() |> Enum.sort()
    end
  end

  @doc "Returns resolved chord tones. Prefers explicit `tones`; otherwise derives from `quality`."
  @spec tones(t()) :: [tone()]
  def tones(%__MODULE__{} = spec) do
    cond do
      is_list(spec.tones) and spec.tones != [] -> spec.tones
      is_atom(spec.quality) -> Map.fetch!(@quality_tones, spec.quality)
      true -> []
    end
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {pitch_class(), integer()}
  def note_name(note_number) when is_integer(note_number) do
    note_name(note_number, :sharp)
  end

  @doc "The note name and octave for a MIDI note number using the requested spelling."
  @spec note_name(integer(), :sharp | :flat) :: {pitch_class(), integer()}
  def note_name(note_number, spelling)
      when is_integer(note_number) and spelling in [:sharp, :flat] do
    octave = div(note_number, 12) - 1
    semitone = rem(note_number, 12)
    note_names = if spelling == :flat, do: @flat_note_names, else: @sharp_note_names
    {Enum.at(note_names, semitone), octave}
  end

  @doc "Returns MIDI number for the harmonic root at the chord octave."
  @spec root_midi_note(t()) :: non_neg_integer()
  def root_midi_note(%__MODULE__{} = spec) do
    midi_note_number(spec.root, spec.octave)
  end

  @doc "Pretty root label preserving sharp/flat identity, e.g. `:a_sharp` -> `A#`, `:b_flat` -> `Bb`."
  @spec root_label(pitch_class()) :: String.t()
  def root_label(root) when is_atom(root) do
    case root do
      :c_flat -> "Cb"
      :b_sharp -> "B#"
      :c_sharp -> "C#"
      :d_flat -> "Db"
      :d_sharp -> "D#"
      :e_flat -> "Eb"
      :f_flat -> "Fb"
      :e_sharp -> "E#"
      :f_sharp -> "F#"
      :g_flat -> "Gb"
      :g_sharp -> "G#"
      :a_flat -> "Ab"
      :a_sharp -> "A#"
      :b_flat -> "Bb"
      _ -> root |> Atom.to_string() |> String.upcase()
    end
  end

  @doc "Human-readable key label, e.g. `%{tonic: :b_flat, mode: :major}` -> `Bb major`."
  @spec key_label(key_spec()) :: String.t()
  def key_label(%{tonic: tonic, mode: mode}) when mode in [:major, :minor] do
    "#{root_label(tonic)} #{Atom.to_string(mode)}"
  end

  @doc "Compact human-readable chord symbol with optional slash bass."
  @spec symbol_label(t()) :: String.t()
  def symbol_label(%__MODULE__{} = spec) do
    root = root_label(spec.root)
    tones = spec |> tones() |> Enum.uniq()
    quality = symbol_quality_suffix(tones)
    explicit = "(#{tones |> Enum.map(&display_tone/1) |> Enum.join(",")})"
    bass = if is_nil(spec.bass), do: "", else: "/" <> root_label(spec.bass)

    case quality do
      nil -> "#{root}#{explicit}#{bass}"
      suffix -> "#{root}#{suffix}#{bass}"
    end
  end

  defp symbol_quality_suffix(tones) do
    set = MapSet.new(tones)

    cond do
      set == MapSet.new(["1", "3", "5"]) -> ""
      set == MapSet.new(["1", "b3", "5"]) -> "m"
      set == MapSet.new(["1", "b3", "b5"]) -> "dim"
      set == MapSet.new(["1", "3", "#5"]) -> "aug"
      set == MapSet.new(["1", "4", "5"]) -> "sus4"
      set == MapSet.new(["1", "2", "5"]) -> "sus2"
      set == MapSet.new(["1", "3", "5", "7"]) -> "maj7"
      set == MapSet.new(["1", "b3", "5", "b7"]) -> "m7"
      set == MapSet.new(["1", "3", "5", "b7"]) -> "7"
      set == MapSet.new(["1", "b3", "b5", "b7"]) -> "m7♭5"
      set == MapSet.new(["1", "b3", "b5", "bb7"]) -> "dim7"
      set == MapSet.new(["1", "3", "5", "7", "9"]) -> "maj9"
      set == MapSet.new(["1", "b3", "5", "b7", "9"]) -> "m9"
      set == MapSet.new(["1", "3", "5", "b7", "9"]) -> "9"
      set == MapSet.new(["1", "b3", "5", "b7", "9", "11"]) -> "m11"
      set == MapSet.new(["1", "3", "5", "7", "9", "11"]) -> "maj11"
      set == MapSet.new(["1", "3", "5", "b7", "9", "13"]) -> "13"
      set == MapSet.new(["1", "3", "5", "6", "9"]) -> "6/9"
      set == MapSet.new(["1", "b3", "5", "6"]) -> "m6"
      set == MapSet.new(["1", "b3", "5", "b7", "11"]) -> "m7(add11)"
      true -> nil
    end
  end

  defp display_tone(tone) when is_binary(tone) do
    tone
    |> String.replace("b", "♭")
    |> String.replace("#", "♯")
  end

  defp midi_note_number(note, octave) do
    semitone = pitch_class_to_semitone(note)

    if is_nil(semitone) do
      raise ArgumentError, "invalid pitch class: #{inspect(note)}"
    end

    (octave + 1) * 12 + semitone
  end

  defp anchored_bass_midi(bass, octave, upper_notes) do
    base = midi_note_number(bass, octave)
    top_anchor = upper_notes |> Enum.min(fn -> base end)

    Stream.iterate(base, &(&1 - 12))
    |> Enum.find(fn value -> value <= top_anchor end)
  end

  defp valid_pitch_class?(root) when is_atom(root) do
    not is_nil(pitch_class_to_semitone(root))
  end

  defp valid_pitch_class?(_root), do: false

  defp valid_key_spec?(%{tonic: tonic, mode: mode}) when mode in [:major, :minor],
    do: valid_pitch_class?(tonic)

  defp valid_key_spec?(_key), do: false

  defp maybe_expand_legacy_modifier(%{tones: tones} = attrs) when is_list(tones), do: attrs

  defp maybe_expand_legacy_modifier(%{quality: quality} = attrs) when is_atom(quality) do
    if Map.has_key?(@quality_tones, quality), do: attrs, else: attrs
  end

  defp maybe_expand_legacy_modifier(%{modifier: modifier} = attrs) do
    case Map.get(@legacy_tones, modifier) do
      nil -> attrs
      tones -> attrs |> Map.put(:tones, tones) |> Map.delete(:modifier)
    end
  end

  defp maybe_expand_legacy_modifier(attrs), do: attrs

  defp pitch_class_to_semitone(note) do
    case note do
      :c -> 0
      :b_sharp -> 0
      :c_sharp -> 1
      :d_flat -> 1
      :d -> 2
      :d_sharp -> 3
      :e_flat -> 3
      :e -> 4
      :f_flat -> 4
      :e_sharp -> 5
      :f -> 5
      :f_sharp -> 6
      :g_flat -> 6
      :g -> 7
      :g_sharp -> 8
      :a_flat -> 8
      :a -> 9
      :a_sharp -> 10
      :b_flat -> 10
      :b -> 11
      :c_flat -> 11
      _ -> nil
    end
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
