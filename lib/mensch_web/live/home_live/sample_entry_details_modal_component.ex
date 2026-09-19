defmodule MenschWeb.HomeLive.SampleEntryDetailsModalComponent do
  use MenschWeb, :live_component

  alias Mensch.ChordSpec
  alias MenschWeb.SampleEntryViz.ChordSpecComponent
  alias MenschWeb.SampleEntryViz.MachineComponent
  alias MenschWeb.SampleEntryViz.TimelineComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="sample-entry-details-overlay"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-4"
      phx-window-keydown="close_sample_entry_details"
      phx-key="escape"
    >
      <button
        type="button"
        class="absolute inset-0"
        phx-click="close_sample_entry_details"
        aria-label="Close sample entry details"
      ></button>

      <div
        id="sample-entry-details-panel"
        phx-click-away="close_sample_entry_details"
        class="ui-radius-modal relative z-10 w-full max-w-3xl border border-zinc-700 bg-zinc-950 p-4"
      >
        <div class="mb-3 flex items-center justify-between border-b border-zinc-700 pb-2">
          <div>
            <div class="text-[11px] uppercase tracking-wide text-zinc-400">
              {chord_details_title(@sample_entry_index)}
            </div>
            <div class="font-mono text-xl text-zinc-100">
              {chord_header_label(@sample_entry, @sample_entry_index)}
            </div>
          </div>
          <button
            type="button"
            phx-click="close_sample_entry_details"
            aria-label="Close sample entry details"
            class="ui-radius-btn flex size-8 items-center justify-center border border-[#ff5d8f]/70 text-[#ff84aa] transition-colors duration-150 hover:bg-[#ff5d8f]/12 hover:text-[#ffc0d4]"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div :if={@sample_entry} class="space-y-3">
          <ChordSpecComponent.panel chord_spec={@sample_entry.chord_spec} />
          <MachineComponent.panel machine={@sample_entry.machine} />

          <TimelineComponent.panel
            timeline_context={@sample_entry.timeline_context}
            sample_context={@sample_context}
          />
        </div>
      </div>
    </div>
    """
  end

  defp chord_header_label(%{chord_spec: %ChordSpec{} = chord_spec}, sample_entry_index)
       when is_integer(sample_entry_index) do
    chord_label(chord_spec)
  end

  defp chord_header_label(_sample_entry, sample_entry_index)
       when is_integer(sample_entry_index) do
    "Chord"
  end

  defp chord_header_label(_sample_entry, _sample_entry_index), do: "Chord"

  defp chord_details_title(sample_entry_index) when is_integer(sample_entry_index),
    do: "Chord Details ##{sample_entry_index}"

  defp chord_details_title(_sample_entry_index), do: "Chord Details"

  defp chord_label(%ChordSpec{} = chord_spec) do
    root = chord_spec.root |> Atom.to_string() |> String.replace("_sharp", "#") |> String.upcase()
    modifier = modifier_label(chord_spec.modifier)
    "#{root} #{modifier} · o#{chord_spec.octave} i#{chord_spec.inversion}"
  end

  defp modifier_label(:major), do: "maj"
  defp modifier_label(:minor), do: "min"
  defp modifier_label(:dominant_seventh), do: "7"
  defp modifier_label(:major_seventh), do: "maj7"
  defp modifier_label(:minor_seventh), do: "m7"
  defp modifier_label(:minor_major_seventh), do: "mMaj7"
  defp modifier_label(:diminished), do: "dim"
  defp modifier_label(:half_diminished), do: "m7b5"
  defp modifier_label(:augmented), do: "aug"
  defp modifier_label(modifier), do: Atom.to_string(modifier)
end
