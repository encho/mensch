defmodule MenschWeb.ChordProgressionsLive do
  use MenschWeb, :live_view

  alias Mensch.ChordProgressions

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:midi_status, Mensch.Midi.Connection.status())
     |> assign(:progressions, ChordProgressions.list_progressions())}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:progression}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Chord Progressions"
          subtitle="Saved chord progressions with playable detail pages."
        />

        <div class="flex items-center justify-end">
          <.link
            navigate={~p"/chord-progressions/new"}
            class="rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
          >
            New Progression
          </.link>
        </div>

        <div class="ui-radius-table border border-zinc-700/60 bg-black/30 p-4">
          <%= if @progressions == [] do %>
            <p class="font-mono text-xs text-zinc-400">No saved chord progressions yet.</p>
          <% else %>
            <div class="space-y-2">
              <.link
                :for={item <- @progressions}
                navigate={~p"/chord-progressions/#{item.id}"}
                class="block rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3 transition-colors duration-150 hover:border-zinc-500"
              >
                <div class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
                  <div class="min-w-0">
                    <p class="truncate font-mono text-sm text-zinc-100">{item.name}</p>
                    <p class="mt-1 line-clamp-2 font-mono text-xs text-zinc-400">
                      {if String.trim(item.description) == "",
                        do: "No description",
                        else: item.description}
                    </p>
                  </div>
                  <div class="shrink-0 text-right font-mono text-[11px] text-zinc-500">
                    <p>{item.chord_count} chords</p>
                    <p>updated {item.updated_at}</p>
                  </div>
                </div>
              </.link>
            </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
