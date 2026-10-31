defmodule Mensch.Harmony.Progression.Middleware.TransposeAll do
  @moduledoc """
  Transposes all chords by a semitone amount.

  To ensure the resolved notes are effectively transposed, this middleware
  updates harmonic identity and voicing anchors together.
  """

  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.ForeignBass
  alias Mensch.Harmony.ChordSpec.HarmonicIdentity
  alias Mensch.Harmony.ChordSpec.Voicing

  @type opts :: [semitones: integer()]

  @spec middleware(opts()) :: (ChordProgression.t() ->
                                 {:ok, ChordProgression.t()} | {:error, term()})
  def middleware(opts \\ []) when is_list(opts) do
    semitones = Keyword.get(opts, :semitones, 12)

    fn progression ->
      with :ok <- validate_semitones(semitones) do
        case progression do
          %ChordProgression{} ->
            {:ok,
             %{
               progression
               | chords: Enum.map(progression.chords, &transpose_chord_spec(&1, semitones))
             }}

          _ ->
            {:error, :invalid_progression}
        end
      end
    end
  end

  defp validate_semitones(value) when is_integer(value), do: :ok
  defp validate_semitones(_value), do: {:error, :semitones_must_be_integer}

  defp transpose_chord_spec(%ChordSpec{} = chord_spec, semitones) do
    {root, octave} =
      transpose_pitch_class_with_octave(
        chord_spec.harmonic_identity.root,
        chord_spec.octave,
        semitones
      )

    {foreign_bass_pc, foreign_bass} =
      transpose_identity_bass_and_settings(chord_spec, semitones)

    harmonic_identity = %HarmonicIdentity{
      root: root,
      quality: chord_spec.harmonic_identity.quality,
      foreign_bass: foreign_bass_pc
    }

    voicing = transpose_voicing(chord_spec.voicing, semitones)

    %ChordSpec{
      chord_spec
      | harmonic_identity: harmonic_identity,
        octave: octave,
        voicing: voicing,
        foreign_bass: foreign_bass
    }
  end

  defp transpose_voicing(%Voicing{} = voicing, semitones) do
    %Voicing{
      voicing
      | center_note: voicing.center_note + semitones,
        range_min: shift_if_integer(voicing.range_min, semitones),
        range_max: shift_if_integer(voicing.range_max, semitones)
    }
  end

  defp transpose_identity_bass_and_settings(
         %ChordSpec{harmonic_identity: %{foreign_bass: nil}} = chord_spec,
         _semitones
       ),
       do: {nil, chord_spec.foreign_bass}

  defp transpose_identity_bass_and_settings(
         %ChordSpec{harmonic_identity: %{foreign_bass: foreign_bass_pc}} = chord_spec,
         semitones
       ) do
    bass_settings =
      case chord_spec.foreign_bass do
        %ForeignBass{} = foreign_bass -> foreign_bass
        _ -> %ForeignBass{}
      end

    case bass_settings.mode do
      :absolute ->
        {new_bass_pitch_class, octave} =
          transpose_pitch_class_with_octave(
            foreign_bass_pc,
            bass_settings.octave,
            semitones
          )

        {new_bass_pitch_class, %ForeignBass{bass_settings | octave: octave}}

      :relative ->
        {new_bass_pitch_class, _octave_unused} =
          transpose_pitch_class_with_octave(
            foreign_bass_pc,
            0,
            semitones
          )

        {new_bass_pitch_class, bass_settings}
    end
  end

  defp shift_if_integer(nil, _delta), do: nil
  defp shift_if_integer(value, delta) when is_integer(value), do: value + delta

  defp transpose_pitch_class_with_octave(pitch_class, octave, semitones) do
    base = ChordSpec.midi_note_number(pitch_class, octave)
    transposed = base + semitones
    new_octave = div(transposed, 12) - 1
    new_pc = semitone_to_pitch_class(rem(transposed + 1200, 12))
    {new_pc, new_octave}
  end

  defp semitone_to_pitch_class(0), do: :c
  defp semitone_to_pitch_class(1), do: :c_sharp
  defp semitone_to_pitch_class(2), do: :d
  defp semitone_to_pitch_class(3), do: :d_sharp
  defp semitone_to_pitch_class(4), do: :e
  defp semitone_to_pitch_class(5), do: :f
  defp semitone_to_pitch_class(6), do: :f_sharp
  defp semitone_to_pitch_class(7), do: :g
  defp semitone_to_pitch_class(8), do: :g_sharp
  defp semitone_to_pitch_class(9), do: :a
  defp semitone_to_pitch_class(10), do: :a_sharp
  defp semitone_to_pitch_class(11), do: :b
end
