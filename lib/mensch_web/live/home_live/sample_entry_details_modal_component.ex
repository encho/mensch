defmodule MenschWeb.HomeLive.SampleEntryDetailsModalComponent do
  use MenschWeb, :live_component

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
        class="relative z-10 w-full max-w-3xl border border-zinc-700 bg-zinc-950 p-4"
      >
        <div class="mb-3 flex items-center justify-between border-b border-zinc-700 pb-2">
          <div>
            <div class="text-[11px] uppercase tracking-wide text-zinc-400">Sample Entry Details</div>
            <div class="font-mono text-sm text-zinc-100">Chord ID {@sample_entry_index}</div>
          </div>
          <button
            type="button"
            phx-click="close_sample_entry_details"
            class="border border-zinc-600 px-2 py-1 text-xs uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-[#2fd5c8] hover:text-[#a6f6ef]"
          >
            Close
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
end
