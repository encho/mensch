defmodule MenschWeb.SampleEntryViz.ChordSpecComponent do
  use MenschWeb, :html

  alias Mensch.ChordSpec

  attr :chord_spec, ChordSpec, required: true

  def panel(assigns) do
    assigns =
      assign(assigns,
        root_label: root_label(assigns.chord_spec.root),
        note_labels: midi_note_labels(assigns.chord_spec)
      )

    ~H"""
    <section class="ui-radius-card border border-zinc-800 bg-zinc-900/50 p-3">
      <div class="mb-2 text-[11px] uppercase tracking-wide text-zinc-400">ChordSpec</div>

      <dl class="grid grid-cols-2 gap-x-4 gap-y-1 font-mono text-[11px] text-zinc-200">
        <dt class="text-zinc-500">Root</dt>
        <dd>{@root_label}</dd>
        <dt class="text-zinc-500">Modifier</dt>
        <dd>{@chord_spec.modifier}</dd>
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
    |> ChordSpec.to_midi_notes()
    |> Enum.map(fn note_number ->
      {note_name, octave} = ChordSpec.note_name(note_number)
      "#{root_label(note_name)}#{octave}(#{note_number})"
    end)
  end

  defp root_label(root) do
    root
    |> Atom.to_string()
    |> String.replace("_sharp", "#")
    |> String.upcase()
  end
end
