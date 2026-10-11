defmodule MenschWeb.SampleEntryViz.ChordSpecComponent do
  use MenschWeb, :html

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver

  attr :chord_spec, ChordSpec, required: true

  def panel(assigns) do
    assigns =
      assign(assigns,
        root_label: root_label(assigns.chord_spec.root),
        quality_label: quality_label(assigns.chord_spec),
        tone_labels: ChordSpec.tones(assigns.chord_spec),
        note_labels: midi_note_labels(assigns.chord_spec)
      )

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
        <dt class="text-zinc-500">Octave</dt>
        <dd>{@chord_spec.octave}</dd>
        <dt class="text-zinc-500">Inversion</dt>
        <dd>{@chord_spec.inversion}</dd>
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

  defp quality_label(%ChordSpec{quality: nil}), do: "-"

  defp quality_label(%ChordSpec{quality: quality}) when is_atom(quality),
    do: Atom.to_string(quality)

  defp foreign_bass_label(nil), do: "-"

  defp foreign_bass_label(%ChordSpec.ForeignBass{} = foreign_bass) do
    mode = Atom.to_string(foreign_bass.mode)
    "#{root_label(foreign_bass.pitch_class)} o#{foreign_bass.octave} (#{mode})"
  end

  defp normalize_chord_spec(%ChordSpec{voicing: nil} = chord_spec) do
    chord_spec
    |> Map.from_struct()
    |> ChordSpec.new!()
  end

  defp normalize_chord_spec(%ChordSpec{} = chord_spec), do: chord_spec
end
