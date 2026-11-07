defmodule MenschWeb.ChordMatrixLive do
  use MenschWeb, :live_view

  alias Mensch.ChordMatrices

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:midi_status, Mensch.Midi.Connection.status())
     |> assign(:new_number_rows, 4)
     |> assign(:new_number_columns, 4)
     |> assign(:chord_matrices, ChordMatrices.list_chord_matrices())}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_event(
        "create_chord_matrix",
        %{"chord_matrix" => %{"number_rows" => rows, "number_columns" => columns}},
        socket
      ) do
    with {:ok, parsed_rows} <- parse_positive_integer(rows),
         {:ok, parsed_columns} <- parse_positive_integer(columns),
         {:ok, _record} <- ChordMatrices.create_chord_matrix(parsed_rows, parsed_columns) do
      {:noreply,
       socket
       |> assign(:new_number_rows, parsed_rows)
       |> assign(:new_number_columns, parsed_columns)
       |> assign(:chord_matrices, ChordMatrices.list_chord_matrices())
       |> put_flash(:info, "Chord matrix created")}
    else
      {:error, :invalid_integer} ->
        {:noreply, put_flash(socket, :error, "Rows and columns must be positive integers")}

      {:error, :invalid_dimension} ->
        {:noreply, put_flash(socket, :error, "Rows and columns must be positive integers")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create chord matrix: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:chord_matrix}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Chord Matrix"
          subtitle="Create and browse chord matrix objects."
        />

        <div class="space-y-2 rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
          <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
            Create New Chord Matrix
          </h3>

          <form phx-submit="create_chord_matrix" class="flex flex-wrap items-end gap-3">
            <label class="space-y-1">
              <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Number Rows
              </span>
              <input
                type="number"
                min="1"
                name="chord_matrix[number_rows]"
                value={@new_number_rows}
                class="w-32 rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
              />
            </label>

            <label class="space-y-1">
              <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Number Columns
              </span>
              <input
                type="number"
                min="1"
                name="chord_matrix[number_columns]"
                value={@new_number_columns}
                class="w-32 rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
              />
            </label>

            <button
              type="submit"
              class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
            >
              Create New Chord Matrix
            </button>
          </form>
        </div>

        <div class="space-y-2 rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
          <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
            Existing Chord Matrices
          </h3>

          <div
            :if={@chord_matrices == []}
            class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
          >
            <p class="font-mono text-xs text-zinc-400">No chord matrices yet.</p>
          </div>

          <div :if={@chord_matrices != []} class="overflow-x-auto">
            <table class="w-full min-w-[680px] text-left font-mono text-[11px] text-zinc-200">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-2 py-1.5 font-normal">ID</th>
                  <th class="px-2 py-1.5 font-normal">Rows</th>
                  <th class="px-2 py-1.5 font-normal">Columns</th>
                  <th class="px-2 py-1.5 font-normal">Updated At</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={matrix <- @chord_matrices}
                  class="border-b border-zinc-700/40 last:border-b-0"
                >
                  <td class="px-2 py-1.5 text-zinc-300">
                    <.link
                      navigate={~p"/chord-matrix/#{matrix.id}"}
                      class="transition-colors duration-150 hover:text-cyan-200"
                    >
                      {matrix.id}
                    </.link>
                  </td>
                  <td class="px-2 py-1.5">{matrix.number_rows}</td>
                  <td class="px-2 py-1.5">{matrix.number_columns}</td>
                  <td class="px-2 py-1.5 text-zinc-400">{matrix.updated_at}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_integer}
end
