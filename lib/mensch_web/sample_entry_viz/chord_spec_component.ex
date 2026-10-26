defmodule MenschWeb.SampleEntryViz.ChordSpecComponent do
  use MenschWeb, :html

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver

  attr :chord_spec, ChordSpec, required: true

  def panel(assigns) do
    chord_spec = normalize_chord_spec(assigns.chord_spec)

    assigns =
      assigns
      |> assign(:chord_spec, chord_spec)
      |> assign(:root_label, root_label(ChordSpec.root(chord_spec)))
      |> assign(:quality_label, quality_label(chord_spec))
      |> assign(:tone_labels, ChordSpec.tones(chord_spec))
      |> assign(:note_labels, midi_note_labels(chord_spec))
      |> assign(:voicing_fields, voicing_fields(chord_spec))
      |> assign(:foreign_bass_pitch_class_label, foreign_bass_pitch_class_label(chord_spec))
      |> assign(:foreign_bass_fields, foreign_bass_fields(chord_spec.foreign_bass))

    ~H"""
    <section class="ui-radius-card border border-zinc-800 bg-zinc-900/50 p-3">
      <div class="mb-2 text-[11px] uppercase tracking-wide text-zinc-400">ChordSpec</div>

      <dl class="grid grid-cols-2 gap-x-4 gap-y-1 font-mono text-[11px] text-zinc-200">
        <dt class="text-zinc-500">Root</dt>
        <dd>{@root_label}</dd>
        <dt class="text-zinc-500">Quality</dt>
        <dd>{@quality_label}</dd>
        <dt class="text-zinc-500">Tones</dt>
        <dd>{Enum.join(@tone_labels, ", ")}</dd>
        <dt class="text-zinc-500">Foreign bass</dt>
        <dd>{foreign_bass_label(@chord_spec.foreign_bass)}</dd>
        <dt class="text-zinc-500">Foreign bass pitch class</dt>
        <dd>{@foreign_bass_pitch_class_label}</dd>
        <dt class="text-zinc-500">Foreign bass mode</dt>
        <dd>{Map.get(@foreign_bass_fields, "mode")}</dd>
        <dt class="text-zinc-500">Foreign bass octave</dt>
        <dd>{Map.get(@foreign_bass_fields, "octave")}</dd>
        <dt class="text-zinc-500">Octave</dt>
        <dd>{@chord_spec.octave}</dd>
        <dt class="text-zinc-500">Inversion</dt>
        <dd>{@chord_spec.inversion}</dd>
        <dt class="text-zinc-500">Voicing type</dt>
        <dd>{Map.get(@voicing_fields, "type")}</dd>
        <dt class="text-zinc-500">Inversion resolution mode</dt>
        <dd>{Map.get(@voicing_fields, "inversion_resolution_mode")}</dd>
        <dt class="text-zinc-500">Center note</dt>
        <dd>{Map.get(@voicing_fields, "center_note")}</dd>
        <dt class="text-zinc-500">Range min</dt>
        <dd>{Map.get(@voicing_fields, "range_min")}</dd>
        <dt class="text-zinc-500">Range max</dt>
        <dd>{Map.get(@voicing_fields, "range_max")}</dd>
        <dt class="text-zinc-500">Voice count</dt>
        <dd>{Map.get(@voicing_fields, "voice_count")}</dd>
        <dt class="text-zinc-500">Doubling</dt>
        <dd>{Map.get(@voicing_fields, "doubling")}</dd>
        <dt class="text-zinc-500">MIDI notes</dt>
        <dd>{Enum.join(@note_labels, ", ")}</dd>
      </dl>
    </section>
    """
  end

  defp midi_note_labels(%ChordSpec{} = chord_spec) do
    chord_spec
    |> normalize_chord_spec()
    |> Resolver.resolve()
    |> Enum.map(fn note_number ->
      {note_name, octave} = ChordSpec.note_name(note_number)
      "#{root_label(note_name)}#{octave}(#{note_number})"
    end)
  end

  defp root_label(root) do
    ChordSpec.root_label(root)
  end

  defp quality_label(%ChordSpec{} = chord_spec),
    do: chord_spec |> ChordSpec.quality() |> Atom.to_string()

  defp foreign_bass_label(nil), do: "-"

  defp foreign_bass_label(%ChordSpec.ForeignBass{} = foreign_bass) do
    mode = Atom.to_string(foreign_bass.mode)
    "o#{foreign_bass.octave} (#{mode})"
  end

  defp foreign_bass_pitch_class_label(%ChordSpec{} = chord_spec) do
    case chord_spec.harmonic_identity.bass_pitch_class do
      pitch_class when is_atom(pitch_class) -> root_label(pitch_class)
      _ -> "-"
    end
  end

  defp normalize_chord_spec(%ChordSpec{voicing: nil} = chord_spec) do
    chord_spec
    |> Map.from_struct()
    |> ChordSpec.new!()
  end

  defp normalize_chord_spec(%ChordSpec{} = chord_spec), do: chord_spec

  defp voicing_fields(%ChordSpec{voicing: voicing}) do
    %{
      "type" => atom_or_dash(voicing.type),
      "inversion_resolution_mode" => atom_or_dash(voicing.inversion_resolution_mode),
      "center_note" => integer_or_dash(voicing.center_note),
      "range_min" => integer_or_dash(voicing.range_min),
      "range_max" => integer_or_dash(voicing.range_max),
      "voice_count" => integer_or_dash(voicing.voice_count),
      "doubling" => atom_or_dash(voicing.doubling)
    }
  end

  defp foreign_bass_fields(nil) do
    %{"mode" => "-", "octave" => "-"}
  end

  defp foreign_bass_fields(%ChordSpec.ForeignBass{} = foreign_bass) do
    %{
      "mode" => atom_or_dash(foreign_bass.mode),
      "octave" => integer_or_dash(foreign_bass.octave)
    }
  end

  defp atom_or_dash(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_or_dash(_value), do: "-"

  defp integer_or_dash(value) when is_integer(value), do: Integer.to_string(value)
  defp integer_or_dash(_value), do: "-"
end
