defmodule Mensch.Harmony.ChordSpec do
  @moduledoc """
  Isolated chord specification for the new harmony engine.

  This module models four independent concepts:

  1. Harmonic identity (`root` + `quality`/`tones`)
  2. Inversion (`inversion`)
  3. Voicing (`voicing`)
  4. Independent optional foreign bass (`foreign_bass`)

  The concrete note generation pipeline is implemented in
  `Mensch.Harmony.Resolver`.
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

  @type quality ::
          :maj
          | :min
          | :maj6
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

  defmodule Voicing do
    @moduledoc """
    Voicing controls register and distribution of already inverted chord tones.
    """

    defstruct type: :close,
              center_note: 60,
              range_min: nil,
              range_max: nil,
              voice_count: nil,
              doubling: :auto,
              inversion_tracking_mode: :per_step_centered

    @type t :: %__MODULE__{
            type: :close | :open,
            center_note: integer(),
            range_min: integer() | nil,
            range_max: integer() | nil,
            voice_count: pos_integer() | nil,
            doubling: :root | :top | :auto | :third | :fifth | :guide_tones | :bass,
            inversion_tracking_mode: :per_step_centered | :anchor_then_wander
          }
  end

  defmodule ForeignBass do
    @moduledoc """
    Independent foreign bass definition.

      `mode` controls how octave is interpreted:

      * `:absolute` - place foreign bass in the explicit octave
      * `:relative` - octave is an offset below the lowest voiced chord note octave
    """

    defstruct pitch_class: nil, octave: 0, mode: :relative

    @type t :: %__MODULE__{
            pitch_class: Mensch.Harmony.ChordSpec.pitch_class(),
            octave: integer(),
            mode: :absolute | :relative
          }
  end

  @enforce_keys [:root, :octave, :inversion]
  defstruct root: nil,
            tones: nil,
            quality: nil,
            octave: nil,
            inversion: nil,
            voicing: nil,
            min_voice_count: 0,
            foreign_bass: nil

  @type t :: %__MODULE__{
          root: pitch_class(),
          tones: [tone()] | nil,
          quality: quality() | nil,
          octave: integer(),
          inversion: integer(),
          voicing: Voicing.t(),
          min_voice_count: non_neg_integer(),
          foreign_bass: ForeignBass.t() | nil
        }

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

  @quality_tones %{
    maj: ["1", "3", "5"],
    min: ["1", "b3", "5"],
    maj6: ["1", "3", "5", "6"],
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

  @sharp_note_names ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a
  @flat_note_names ~w(c d_flat d e_flat e f g_flat g a_flat a b_flat b)a

  @doc "Builds and validates a harmony chord spec from a map."
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    spec =
      struct(__MODULE__, attrs)
      |> normalize_voicing()
      |> normalize_foreign_bass()
      |> set_min_voice_count()

    case validate(spec) do
      :ok -> {:ok, spec}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Builds and validates a harmony chord spec from a map, raising on errors."
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, spec} -> spec
      {:error, reason} -> raise ArgumentError, "invalid harmony chord spec: #{inspect(reason)}"
    end
  end

  @doc "Validates a harmony chord spec."
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

      true ->
        validate_voicing(spec.voicing)
        |> validate_voice_count_against_min(spec)
        |> validate_foreign_bass(spec.foreign_bass)
    end
  end

  @doc "Returns minimum voice count implied by the chord tones for this spec."
  @spec min_voice_count(t()) :: non_neg_integer()
  def min_voice_count(%__MODULE__{} = spec) do
    spec
    |> tones()
    |> Enum.uniq()
    |> length()
  end

  @doc "Returns minimum voice count implied by a chord quality."
  @spec min_voice_count_for_quality(quality()) :: pos_integer()
  def min_voice_count_for_quality(quality) when is_atom(quality) do
    @quality_tones
    |> Map.fetch!(quality)
    |> Enum.uniq()
    |> length()
  end

  @doc "Returns resolved tones. Explicit tones override quality-derived tones."
  @spec tones(t()) :: [tone()]
  def tones(%__MODULE__{} = spec) do
    cond do
      is_list(spec.tones) and spec.tones != [] -> spec.tones
      is_atom(spec.quality) -> Map.fetch!(@quality_tones, spec.quality)
      true -> []
    end
  end

  @doc "Returns semitone intervals for resolved tones."
  @spec tone_intervals(t()) :: [integer()]
  def tone_intervals(%__MODULE__{} = spec) do
    spec
    |> tones()
    |> Enum.uniq()
    |> Enum.map(&Map.fetch!(@tone_intervals, &1))
    |> Enum.sort()
  end

  @doc "Returns the semitone interval for a single tone token."
  @spec tone_interval(tone()) :: integer()
  def tone_interval(tone) when is_binary(tone) do
    Map.fetch!(@tone_intervals, tone)
  end

  @doc "Returns semitone for a pitch class, or nil if invalid."
  @spec pitch_class_to_semitone(pitch_class()) :: integer() | nil
  def pitch_class_to_semitone(note) do
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

  @doc "Converts pitch class and octave to MIDI note number."
  @spec midi_note_number(pitch_class(), integer()) :: integer()
  def midi_note_number(note, octave) when is_integer(octave) do
    semitone = pitch_class_to_semitone(note)

    if is_nil(semitone) do
      raise ArgumentError, "invalid pitch class: #{inspect(note)}"
    end

    (octave + 1) * 12 + semitone
  end

  @doc "Pretty root label preserving sharp/flat identity."
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

  @doc "Compact human-readable chord symbol with optional foreign bass."
  @spec symbol_label(t()) :: String.t()
  def symbol_label(%__MODULE__{} = spec) do
    root = root_label(spec.root)
    tones = spec |> tones() |> Enum.uniq()
    quality = symbol_quality_suffix(tones)
    explicit = "(" <> Enum.map_join(tones, ",", &display_tone/1) <> ")"

    bass =
      case spec.foreign_bass do
        %ForeignBass{pitch_class: pitch_class} -> "/" <> root_label(pitch_class)
        _ -> ""
      end

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
      set == MapSet.new(["1", "3", "5", "6"]) -> "6"
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

  defp valid_pitch_class?(root) when is_atom(root), do: not is_nil(pitch_class_to_semitone(root))
  defp valid_pitch_class?(_root), do: false

  defp normalize_voicing(%__MODULE__{voicing: %Voicing{} = voicing} = spec),
    do: %{spec | voicing: voicing}

  defp normalize_voicing(%__MODULE__{voicing: voicing} = spec) when is_map(voicing) do
    %{spec | voicing: struct(Voicing, voicing)}
  end

  defp normalize_voicing(%__MODULE__{voicing: nil} = spec), do: %{spec | voicing: %Voicing{}}

  defp normalize_voicing(%__MODULE__{} = spec), do: spec

  defp normalize_foreign_bass(%__MODULE__{foreign_bass: %ForeignBass{} = bass} = spec),
    do: %{spec | foreign_bass: bass}

  defp normalize_foreign_bass(%__MODULE__{foreign_bass: bass} = spec) when is_map(bass) do
    %{spec | foreign_bass: struct(ForeignBass, bass)}
  end

  defp normalize_foreign_bass(%__MODULE__{} = spec), do: spec

  defp set_min_voice_count(%__MODULE__{} = spec),
    do: %{spec | min_voice_count: min_voice_count(spec)}

  defp validate_voicing(%Voicing{} = voicing) do
    cond do
      voicing.type not in [:close, :open] ->
        {:error, {:invalid_voicing_type, voicing.type}}

      not is_integer(voicing.center_note) ->
        {:error, {:invalid_center_note, voicing.center_note}}

      not is_nil(voicing.range_min) and not is_integer(voicing.range_min) ->
        {:error, {:invalid_range_min, voicing.range_min}}

      not is_nil(voicing.range_max) and not is_integer(voicing.range_max) ->
        {:error, {:invalid_range_max, voicing.range_max}}

      is_integer(voicing.range_min) and is_integer(voicing.range_max) and
          voicing.range_min > voicing.range_max ->
        {:error, {:invalid_range, {voicing.range_min, voicing.range_max}}}

      not is_nil(voicing.voice_count) and
          (not is_integer(voicing.voice_count) or voicing.voice_count <= 0) ->
        {:error, {:invalid_voice_count, voicing.voice_count}}

      voicing.doubling not in [:root, :top, :auto, :third, :fifth, :guide_tones, :bass] ->
        {:error, {:invalid_doubling, voicing.doubling}}

      voicing.inversion_tracking_mode not in [:per_step_centered, :anchor_then_wander] ->
        {:error, {:invalid_inversion_tracking_mode, voicing.inversion_tracking_mode}}

      true ->
        :ok
    end
  end

  defp validate_voicing(other), do: {:error, {:invalid_voicing, other}}

  defp validate_voice_count_against_min(:ok, %__MODULE__{} = spec) do
    voice_count = spec.voicing.voice_count

    if is_integer(voice_count) and voice_count < spec.min_voice_count do
      {:error, {:invalid_voice_count_below_min, {voice_count, spec.min_voice_count}}}
    else
      :ok
    end
  end

  defp validate_voice_count_against_min(error, _spec), do: error

  defp validate_foreign_bass(:ok, nil), do: :ok

  defp validate_foreign_bass(:ok, %ForeignBass{} = bass) do
    cond do
      not valid_pitch_class?(bass.pitch_class) ->
        {:error, {:invalid_foreign_bass_pitch_class, bass.pitch_class}}

      bass.mode not in [:absolute, :relative] ->
        {:error, {:invalid_foreign_bass_mode, bass.mode}}

      not is_integer(bass.octave) ->
        {:error, {:invalid_foreign_bass_octave, bass.octave}}

      bass.mode == :relative and bass.octave < 0 ->
        {:error, {:invalid_foreign_bass_relative_octave, bass.octave}}

      true ->
        :ok
    end
  end

  defp validate_foreign_bass(:ok, other), do: {:error, {:invalid_foreign_bass, other}}
  defp validate_foreign_bass(error, _foreign_bass), do: error
end
