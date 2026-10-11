defmodule Mensch.Harmony.ChordSpec.Parameters do
  @moduledoc """
  Typed chord parameter boundary used by UI persistence and editing flows.

  This struct represents user-facing chord settings before they are converted
  into `Mensch.Harmony.ChordSpec` for resolution.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.ForeignBass
  alias Mensch.Harmony.ChordSpec.Voicing

  defstruct root: :c,
            quality: :maj7,
            octave: 3,
            inversion: 0,
            voicing_type: :close,
            inversion_resolution_mode: :per_step_centered,
            center_note: 60,
            range_min: nil,
            range_max: nil,
            voice_count: nil,
            doubling: :auto,
            foreign_bass_mode: :relative,
            foreign_bass_pitch_class: nil,
            foreign_bass_octave: 0

  @type t :: %__MODULE__{
          root: ChordSpec.pitch_class(),
          quality: ChordSpec.quality(),
          octave: integer(),
          inversion: integer(),
          voicing_type: :close | :open,
          inversion_resolution_mode: :per_step_centered | :anchor_then_wander,
          center_note: integer(),
          range_min: integer() | nil,
          range_max: integer() | nil,
          voice_count: pos_integer() | nil,
          doubling: :root | :top | :auto | :third | :fifth | :guide_tones | :bass,
          foreign_bass_mode: :relative | :absolute,
          foreign_bass_pitch_class: ChordSpec.pitch_class() | nil,
          foreign_bass_octave: integer()
        }

  @spec from_values_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_values_map(values) when is_map(values) do
    with {:ok, root} <- parse_pitch_class(Map.get(values, "root", "c")),
         {:ok, quality} <- parse_quality(Map.get(values, "quality", "maj7")),
         {:ok, octave} <- parse_integer(Map.get(values, "octave", 3), "octave"),
         {:ok, inversion} <- parse_integer(Map.get(values, "inversion", 0), "inversion"),
         {:ok, voicing_type} <- parse_voicing_type(Map.get(values, "voicing_type", "close")),
         {:ok, inversion_resolution_mode} <-
           parse_inversion_resolution_mode(
             Map.get(values, "inversion_resolution_mode", "per_step_centered")
           ),
         {:ok, center_note} <- parse_integer(Map.get(values, "center_note", 60), "center_note"),
         {:ok, range_min} <-
           parse_optional_integer(Map.get(values, "range_min", nil), "range_min"),
         {:ok, range_max} <-
           parse_optional_integer(Map.get(values, "range_max", nil), "range_max"),
         {:ok, voice_count} <-
           parse_optional_integer(Map.get(values, "voice_count", nil), "voice_count"),
         {:ok, doubling} <- parse_doubling(Map.get(values, "doubling", "auto")),
         {:ok, foreign_bass_mode} <-
           parse_foreign_bass_mode(Map.get(values, "foreign_bass_mode", "relative")),
         {:ok, foreign_bass_pitch_class} <-
           parse_optional_pitch_class(Map.get(values, "foreign_bass_pitch_class", nil)),
         {:ok, foreign_bass_octave} <-
           parse_integer(Map.get(values, "foreign_bass_octave", 0), "foreign_bass_octave") do
      {:ok,
       %__MODULE__{
         root: root,
         quality: quality,
         octave: octave,
         inversion: inversion,
         voicing_type: voicing_type,
         inversion_resolution_mode: inversion_resolution_mode,
         center_note: center_note,
         range_min: range_min,
         range_max: range_max,
         voice_count: voice_count,
         doubling: doubling,
         foreign_bass_mode: foreign_bass_mode,
         foreign_bass_pitch_class: foreign_bass_pitch_class,
         foreign_bass_octave: foreign_bass_octave
       }}
    end
  end

  @spec to_values_map(t()) :: map()
  def to_values_map(%__MODULE__{} = params) do
    %{
      "root" => Atom.to_string(params.root),
      "quality" => Atom.to_string(params.quality),
      "octave" => Integer.to_string(params.octave),
      "inversion" => Integer.to_string(params.inversion),
      "voicing_type" => Atom.to_string(params.voicing_type),
      "inversion_resolution_mode" => Atom.to_string(params.inversion_resolution_mode),
      "center_note" => Integer.to_string(params.center_note),
      "range_min" =>
        if(is_integer(params.range_min), do: Integer.to_string(params.range_min), else: ""),
      "range_max" =>
        if(is_integer(params.range_max), do: Integer.to_string(params.range_max), else: ""),
      "voice_count" =>
        if(is_integer(params.voice_count), do: Integer.to_string(params.voice_count), else: ""),
      "doubling" => Atom.to_string(params.doubling),
      "foreign_bass_mode" => Atom.to_string(params.foreign_bass_mode),
      "foreign_bass_pitch_class" =>
        if(is_atom(params.foreign_bass_pitch_class),
          do: Atom.to_string(params.foreign_bass_pitch_class),
          else: ""
        ),
      "foreign_bass_octave" => Integer.to_string(params.foreign_bass_octave)
    }
  end

  @spec to_chord_spec_attrs(t()) :: map()
  def to_chord_spec_attrs(%__MODULE__{} = params) do
    %{
      root: params.root,
      quality: params.quality,
      octave: params.octave,
      inversion: params.inversion,
      voicing: %Voicing{
        type: params.voicing_type,
        inversion_resolution_mode: params.inversion_resolution_mode,
        center_note: params.center_note,
        range_min: params.range_min,
        range_max: params.range_max,
        voice_count: params.voice_count,
        doubling: params.doubling
      },
      foreign_bass: to_foreign_bass(params)
    }
  end

  defp to_foreign_bass(%__MODULE__{foreign_bass_pitch_class: nil}), do: nil

  defp to_foreign_bass(%__MODULE__{} = params) do
    %ForeignBass{
      pitch_class: params.foreign_bass_pitch_class,
      mode: params.foreign_bass_mode,
      octave: params.foreign_bass_octave
    }
  end

  defp parse_optional_pitch_class(nil), do: {:ok, nil}
  defp parse_optional_pitch_class(""), do: {:ok, nil}
  defp parse_optional_pitch_class(value), do: parse_pitch_class(value)

  defp parse_pitch_class(value) when is_binary(value) do
    case value do
      "c" -> {:ok, :c}
      "c_flat" -> {:ok, :c_flat}
      "b_sharp" -> {:ok, :b_sharp}
      "c_sharp" -> {:ok, :c_sharp}
      "d_flat" -> {:ok, :d_flat}
      "d" -> {:ok, :d}
      "d_sharp" -> {:ok, :d_sharp}
      "e_flat" -> {:ok, :e_flat}
      "e" -> {:ok, :e}
      "f_flat" -> {:ok, :f_flat}
      "e_sharp" -> {:ok, :e_sharp}
      "f" -> {:ok, :f}
      "f_sharp" -> {:ok, :f_sharp}
      "g_flat" -> {:ok, :g_flat}
      "g" -> {:ok, :g}
      "g_sharp" -> {:ok, :g_sharp}
      "a_flat" -> {:ok, :a_flat}
      "a" -> {:ok, :a}
      "a_sharp" -> {:ok, :a_sharp}
      "b_flat" -> {:ok, :b_flat}
      "b" -> {:ok, :b}
      _ -> {:error, "invalid root pitch class"}
    end
  end

  defp parse_pitch_class(value) when is_atom(value) do
    if is_nil(ChordSpec.pitch_class_to_semitone(value)) do
      {:error, "invalid root pitch class"}
    else
      {:ok, value}
    end
  end

  defp parse_pitch_class(_value), do: {:error, "invalid root pitch class"}

  defp parse_quality(value) when is_binary(value) do
    case String.to_existing_atom(value) do
      atom
      when atom in [
             :maj,
             :min,
             :maj6,
             :maj7,
             :min7,
             :dom7,
             :sus2,
             :sus4,
             :maj9,
             :min9,
             :dom9,
             :maj11,
             :min11,
             :dom13,
             :six_nine,
             :min6,
             :dim,
             :half_dim,
             :dim7,
             :aug,
             :min7_add11
           ] ->
        {:ok, atom}

      _ ->
        {:error, "invalid quality"}
    end
  rescue
    ArgumentError -> {:error, "invalid quality"}
  end

  defp parse_quality(value) when is_atom(value) do
    parse_quality(Atom.to_string(value))
  end

  defp parse_quality(_value), do: {:error, "invalid quality"}

  defp parse_voicing_type("close"), do: {:ok, :close}
  defp parse_voicing_type("open"), do: {:ok, :open}
  defp parse_voicing_type(:close), do: {:ok, :close}
  defp parse_voicing_type(:open), do: {:ok, :open}
  defp parse_voicing_type(_), do: {:error, "invalid voicing type"}

  defp parse_inversion_resolution_mode("per_step_centered"), do: {:ok, :per_step_centered}
  defp parse_inversion_resolution_mode("anchor_then_wander"), do: {:ok, :anchor_then_wander}
  defp parse_inversion_resolution_mode(:per_step_centered), do: {:ok, :per_step_centered}
  defp parse_inversion_resolution_mode(:anchor_then_wander), do: {:ok, :anchor_then_wander}
  defp parse_inversion_resolution_mode(_), do: {:error, "invalid inversion resolution mode"}

  defp parse_doubling("root"), do: {:ok, :root}
  defp parse_doubling("top"), do: {:ok, :top}
  defp parse_doubling("auto"), do: {:ok, :auto}
  defp parse_doubling("third"), do: {:ok, :third}
  defp parse_doubling("fifth"), do: {:ok, :fifth}
  defp parse_doubling("guide_tones"), do: {:ok, :guide_tones}
  defp parse_doubling("bass"), do: {:ok, :bass}
  defp parse_doubling(:root), do: {:ok, :root}
  defp parse_doubling(:top), do: {:ok, :top}
  defp parse_doubling(:auto), do: {:ok, :auto}
  defp parse_doubling(:third), do: {:ok, :third}
  defp parse_doubling(:fifth), do: {:ok, :fifth}
  defp parse_doubling(:guide_tones), do: {:ok, :guide_tones}
  defp parse_doubling(:bass), do: {:ok, :bass}
  defp parse_doubling(_), do: {:error, "invalid doubling"}

  defp parse_foreign_bass_mode("relative"), do: {:ok, :relative}
  defp parse_foreign_bass_mode("absolute"), do: {:ok, :absolute}
  defp parse_foreign_bass_mode(:relative), do: {:ok, :relative}
  defp parse_foreign_bass_mode(:absolute), do: {:ok, :absolute}
  defp parse_foreign_bass_mode(_), do: {:error, "foreign_bass_mode is invalid"}

  defp parse_integer(value, _field_name) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, field_name) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "#{field_name} must be an integer"}
    end
  end

  defp parse_integer(_value, field_name), do: {:error, "#{field_name} must be an integer"}

  defp parse_optional_integer(nil, _field_name), do: {:ok, nil}
  defp parse_optional_integer("", _field_name), do: {:ok, nil}
  defp parse_optional_integer(value, field_name), do: parse_integer(value, field_name)
end
