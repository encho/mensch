defmodule MenschWeb.ChordMatrixShowLive do
  use MenschWeb, :live_view

  alias Mensch.ChordMatrices

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:midi_status, Mensch.Midi.Connection.status())
     |> assign(:record, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case ChordMatrices.fetch_chord_matrix(id) do
      {:ok, record} ->
        {:noreply, assign(socket, :record, record)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Chord matrix not found")
         |> push_navigate(to: ~p"/chord-matrix")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to load chord matrix: #{inspect(reason)}")
         |> push_navigate(to: ~p"/chord-matrix")}
    end
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:chord_matrix}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title={if @record, do: "Chord Matrix #{@record.id}", else: "Chord Matrix"}
          subtitle="Matrix detail and board view."
        />

        <div :if={@record} class="space-y-3">
          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
              Attributes
            </h3>
            <dl class="mt-2 grid gap-2 font-mono text-xs text-zinc-200 md:grid-cols-2">
              <div>
                <dt class="text-zinc-400">ID</dt>
                <dd class="break-all">{@record.id}</dd>
              </div>
              <div>
                <dt class="text-zinc-400">Rows</dt>
                <dd>{@record.chord_matrix.number_rows}</dd>
              </div>
              <div>
                <dt class="text-zinc-400">Columns</dt>
                <dd>{@record.chord_matrix.number_columns}</dd>
              </div>
              <div>
                <dt class="text-zinc-400">Updated At</dt>
                <dd>{@record.updated_at}</dd>
              </div>
            </dl>
          </div>

          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
              Matrix Board
            </h3>

            <div class="mt-3 overflow-x-auto">
              <div
                class="inline-grid gap-1"
                style={
                  "grid-template-columns: repeat(#{@record.chord_matrix.number_columns}, minmax(0, 6rem));"
                }
              >
                <div
                  :for={row <- 0..(@record.chord_matrix.number_rows - 1)}
                  class="contents"
                >
                  <div
                    :for={col <- 0..(@record.chord_matrix.number_columns - 1)}
                    class="aspect-square w-full rounded-sm border border-zinc-700/60 bg-zinc-900/70"
                  >
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
