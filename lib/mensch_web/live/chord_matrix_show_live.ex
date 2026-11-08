defmodule MenschWeb.ChordMatrixShowLive do
  use MenschWeb, :live_view

  alias Mensch.ChordMatrices
  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordMatrix
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver
  alias MenschWeb.FullPianoKeyboard

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:midi_status, Mensch.Midi.Connection.status())
     |> assign(:record, nil)
     |> assign(:selected_pad, nil)
     |> assign(:chord_matrix_play_mode, false)
     |> assign(:keyboard_active_notes, [])
     |> assign(:keyboard_source, "No chord selected")
     |> assign(:progressions, ChordProgressions.list_progressions())
     |> assign(:expanded_progression_ids, MapSet.new())
     |> assign(:progression_records, %{})
     |> assign(:preview_note_channels, [])
     |> assign(:preview_stop_ref, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case ChordMatrices.fetch_chord_matrix(id) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:record, record)
         |> assign_keyboard_from_selected_pad()}

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
  def handle_event("select_pad", %{"row" => row, "column" => column}, socket) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         {:ok, normalized_column} <- parse_non_negative_integer(column),
         :ok <-
           ensure_selected_pad_in_bounds(socket.assigns.record, normalized_row, normalized_column) do
      socket =
        socket
        |> assign(:selected_pad, {normalized_row, normalized_column})
        |> assign_keyboard_from_selected_pad()

      if socket.assigns.chord_matrix_play_mode do
        case pad_assignment(socket.assigns.record, normalized_row, normalized_column) do
          %{chord_spec: %ChordSpec{} = chord_spec} ->
            play_notes_for_3s(socket, Resolver.resolve(chord_spec))

          _ ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid pad selection")}
    end
  end

  @impl true
  def handle_event("toggle_matrix_play_mode", _params, socket) do
    {:noreply, assign(socket, :chord_matrix_play_mode, !socket.assigns.chord_matrix_play_mode)}
  end

  @impl true
  def handle_event("clear_selected_pad_assignment", _params, socket) do
    case socket.assigns.selected_pad do
      {row, column} when is_integer(row) and is_integer(column) ->
        case ChordMatrices.clear_pad_assignment(socket.assigns.record.id, row, column) do
          {:ok, record} ->
            {:noreply, socket |> assign(:record, record) |> put_flash(:info, "Pad cleared")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to clear pad assignment: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Select a pad first")}
    end
  end

  @impl true
  def handle_event("toggle_progression", %{"id" => id}, socket) do
    if MapSet.member?(socket.assigns.expanded_progression_ids, id) do
      {:noreply,
       assign(
         socket,
         :expanded_progression_ids,
         MapSet.delete(socket.assigns.expanded_progression_ids, id)
       )}
    else
      case ensure_progression_loaded(socket, id) do
        {:ok, socket_with_progression} ->
          {:noreply,
           assign(
             socket_with_progression,
             :expanded_progression_ids,
             MapSet.put(socket.assigns.expanded_progression_ids, id)
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to load progression: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event(
        "assign_pad_chord",
        %{"progression_id" => progression_id, "chord_index" => chord_index},
        socket
      ) do
    with {row, column} when is_integer(row) and is_integer(column) <- socket.assigns.selected_pad,
         {:ok, progression} <- fetch_progression_for_assignment(socket, progression_id),
         {:ok, parsed_index} <- parse_non_negative_integer(chord_index),
         %ChordSpec{} = chord_spec <- Enum.at(progression.chords, parsed_index),
         {:ok, record} <-
           ChordMatrices.assign_chord_to_pad(socket.assigns.record.id, row, column, chord_spec, %{
             source_progression_id: progression_id,
             source_progression_name: progression.name,
             source_chord_index: parsed_index
           }) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> put_flash(:info, "Assigned chord to pad")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a pad first")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Assignment failed: #{inspect(reason)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid chord assignment")}
    end
  end

  @impl true
  def handle_event(
        "play_progression_chord",
        %{"progression_id" => progression_id, "chord_index" => chord_index},
        socket
      ) do
    with {:ok, progression} <- fetch_progression_for_assignment(socket, progression_id),
         {:ok, parsed_index} <- parse_non_negative_integer(chord_index),
         %ChordSpec{} = chord_spec <- Enum.at(progression.chords, parsed_index) do
      play_notes_for_3s(
        socket,
        Resolver.resolve(chord_spec),
        "Previewing #{ChordSpec.symbol_label(chord_spec)}"
      )
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Preview failed: #{inspect(reason)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid chord selection")}
    end
  end

  @impl true
  def handle_info({:stop_preview_notes, stop_ref}, socket) do
    if socket.assigns.preview_stop_ref == stop_ref do
      {:noreply, stop_preview(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:chord_matrix}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title={if @record, do: "Chord Matrix #{@record.id}", else: "Chord Matrix"}
          subtitle={if(@record, do: "Updated #{format_timestamp(@record.updated_at)}", else: "")}
        />

        <div :if={@record} class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
          <div class="space-y-3">
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <div class="flex flex-wrap items-center gap-2">
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                  Size
                </span>
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-xs text-zinc-100">
                  {@record.chord_matrix.number_rows} rows x {@record.chord_matrix.number_columns} columns
                </span>
              </div>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                  Matrix Board
                </h3>

                <div class="flex items-center gap-2">
                  <p class="font-mono text-[11px] text-zinc-400">
                    Click a pad, then assign a chord from the side panel.
                  </p>

                  <button
                    id="toggle-matrix-play-mode"
                    type="button"
                    phx-click="toggle_matrix_play_mode"
                    role="switch"
                    aria-checked={to_string(@chord_matrix_play_mode)}
                    class="group inline-flex items-center gap-2 rounded-sm border border-zinc-600/80 bg-zinc-900/70 px-2 py-1.5 transition-colors duration-150 hover:border-zinc-400"
                  >
                    <span class="font-mono text-[10px] uppercase tracking-wide text-zinc-200">Play Mode</span>
                    <span class={[
                      "relative h-4 w-8 rounded-full border transition-colors duration-200",
                      if(@chord_matrix_play_mode,
                        do: "border-emerald-300/90 bg-emerald-500/60",
                        else: "border-zinc-500/80 bg-zinc-800"
                      )
                    ]}>
                      <span class={[
                        "absolute top-0.5 size-2.5 rounded-full bg-zinc-100 transition-transform duration-200",
                        if(@chord_matrix_play_mode, do: "translate-x-4", else: "translate-x-0.5")
                      ]}></span>
                    </span>
                  </button>
                </div>
              </div>

              <div class="mt-3 space-y-2 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2">
                <div class="flex items-center justify-between gap-2">
                  <h4 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                    Active Chord Keyboard
                  </h4>
                  <p class="truncate font-mono text-[11px] text-zinc-400">{@keyboard_source}</p>
                </div>

                <FullPianoKeyboard.keyboard
                  id="chord-matrix-active-keyboard"
                  keys={piano_keys(@keyboard_active_notes)}
                  height_class="h-28"
                  show_bottom_lane={false}
                  color_mode={:dark}
                />
              </div>

              <div class="mt-3 overflow-x-auto">
                <div
                  id="chord-matrix-board"
                  class="inline-grid gap-1"
                  style={
                    "grid-template-columns: repeat(#{@record.chord_matrix.number_columns}, minmax(0, 6rem));"
                  }
                >
                  <div :for={row <- 0..(@record.chord_matrix.number_rows - 1)} class="contents">
                    <button
                      :for={col <- 0..(@record.chord_matrix.number_columns - 1)}
                      id={"pad-#{row}-#{col}"}
                      type="button"
                      phx-click="select_pad"
                      phx-value-row={row}
                      phx-value-column={col}
                      class={
                        pad_cell_classes(
                          @selected_pad == {row, col},
                          pad_assignment(@record, row, col) != nil
                        )
                      }
                    >
                      <%= case pad_assignment(@record, row, col) do %>
                        <% nil -> %>
                          <span class="flex h-full w-full items-center justify-center font-mono text-[10px] text-zinc-500">
                            {row},{col}
                          </span>
                        <% assignment -> %>
                          <span class="flex h-full w-full items-center justify-center">
                            <span class="w-full truncate text-center font-mono text-base font-semibold leading-none tracking-tight text-inherit">
                              {ChordSpec.symbol_label(assignment.chord_spec)}
                            </span>
                          </span>
                      <% end %>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <aside class="space-y-3">
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                Selected Pad
              </h3>

              <%= case @selected_pad do %>
                <% {row, column} -> %>
                  <p class="mt-2 font-mono text-xs text-zinc-200">
                    Row {row + 1}, Column {column + 1}
                  </p>

                  <%= case pad_assignment(@record, row, column) do %>
                    <% nil -> %>
                      <p class="mt-2 font-mono text-xs text-zinc-400">No chord assigned.</p>
                    <% assignment -> %>
                      <div class="mt-2 space-y-1 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2">
                        <p class="font-mono text-xs text-zinc-200">
                          {ChordSpec.symbol_label(assignment.chord_spec)}
                        </p>
                        <p class="font-mono text-[11px] text-zinc-400">
                          from {assignment.source_progression_name}
                        </p>
                        <p class="font-mono text-[11px] text-zinc-500">
                          chord #{assignment.source_chord_index + 1}
                        </p>
                      </div>

                      <button
                        type="button"
                        phx-click="clear_selected_pad_assignment"
                        class="mt-2 rounded-sm border border-rose-700/80 bg-rose-900/20 px-2.5 py-1.5 font-mono text-[11px] text-rose-200 transition-colors duration-150 hover:border-rose-500"
                      >
                        Clear Pad
                      </button>
                  <% end %>
                <% nil -> %>
                  <p class="mt-2 font-mono text-xs text-zinc-400">Select a pad on the board.</p>
              <% end %>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                Chord Progressions
              </h3>

              <div
                :if={@progressions == []}
                class="mt-2 rounded-sm border border-zinc-700/60 bg-zinc-950/70 p-2"
              >
                <p class="font-mono text-xs text-zinc-400">No stored progressions found.</p>
              </div>

              <div :if={@progressions != []} class="mt-2 space-y-2">
                <div
                  :for={item <- @progressions}
                  class="rounded-sm border border-zinc-700/70 bg-zinc-950/70"
                >
                  <button
                    id={"toggle-progression-#{item.id}"}
                    type="button"
                    phx-click="toggle_progression"
                    phx-value-id={item.id}
                    class="flex w-full items-center justify-between px-2.5 py-2 text-left"
                  >
                    <span class="min-w-0 truncate font-mono text-xs text-zinc-100">{item.name}</span>
                    <span class="font-mono text-[10px] text-zinc-400">
                      {if MapSet.member?(@expanded_progression_ids, item.id), do: "Hide", else: "Show"}
                    </span>
                  </button>

                  <div
                    :if={MapSet.member?(@expanded_progression_ids, item.id)}
                    class="border-t border-zinc-700/60 px-2 py-2"
                  >
                    <%= case Map.get(@progression_records, item.id) do %>
                      <% nil -> %>
                        <p class="font-mono text-xs text-zinc-400">Unable to load progression.</p>
                      <% progression_record -> %>
                        <div class="space-y-1.5">
                          <div
                            :for={
                              {chord_spec, chord_index} <-
                                Enum.with_index(progression_record.progression.chords)
                            }
                            class="flex items-center gap-1 rounded-sm border border-zinc-700/60 bg-zinc-900/70 p-1"
                          >
                            <button
                              type="button"
                              phx-click="play_progression_chord"
                              phx-value-progression_id={item.id}
                              phx-value-chord_index={chord_index}
                              class="rounded-sm border border-emerald-600/80 bg-emerald-800/20 px-1.5 py-1 font-mono text-[10px] text-emerald-100 transition-colors duration-150 hover:border-emerald-400"
                            >
                              Play
                            </button>

                            <span class="min-w-0 flex-1 truncate font-mono text-[11px] text-zinc-100">
                              {ChordSpec.symbol_label(chord_spec)}
                            </span>

                            <button
                              id={"assign-#{item.id}-#{chord_index}"}
                              type="button"
                              phx-click="assign_pad_chord"
                              phx-value-progression_id={item.id}
                              phx-value-chord_index={chord_index}
                              disabled={is_nil(@selected_pad)}
                              class="rounded-sm border border-sky-500/80 bg-sky-900/20 px-1.5 py-1 font-mono text-[10px] text-sky-100 transition-colors duration-150 enabled:hover:border-sky-300 disabled:cursor-not-allowed disabled:opacity-40"
                            >
                              Assign
                            </button>
                          </div>
                        </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_non_negative_integer(_value), do: {:error, :invalid_integer}

  defp ensure_selected_pad_in_bounds(nil, _row, _column), do: {:error, :invalid_record}

  defp ensure_selected_pad_in_bounds(record, row, column) do
    if row < record.chord_matrix.number_rows and column < record.chord_matrix.number_columns do
      :ok
    else
      {:error, :out_of_bounds}
    end
  end

  defp ensure_progression_loaded(socket, id) do
    case Map.fetch(socket.assigns.progression_records, id) do
      {:ok, _record} ->
        {:ok, socket}

      :error ->
        case ChordProgressions.fetch_progression(id) do
          {:ok, progression_record} ->
            {:ok,
             assign(
               socket,
               :progression_records,
               Map.put(socket.assigns.progression_records, id, progression_record)
             )}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_progression_for_assignment(socket, progression_id) do
    case Map.fetch(socket.assigns.progression_records, progression_id) do
      {:ok, progression_record} ->
        {:ok, progression_record.progression}

      :error ->
        case ChordProgressions.fetch_progression(progression_id) do
          {:ok, progression_record} -> {:ok, progression_record.progression}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp pad_assignment(record, row, col) do
    ChordMatrix.assignment_at(record.chord_matrix, row, col)
  end

  defp pad_cell_classes(selected?, assigned?) do
    [
      "aspect-square w-full rounded-sm border px-1.5 py-1 text-left outline-none",
      "transition-[background-color,border-color,color,box-shadow,transform] duration-200 ease-out",
      "focus-visible:ring-2 focus-visible:ring-sky-300/80 focus-visible:ring-offset-0",
      if(assigned?,
        do:
          "border-emerald-500/70 bg-emerald-700/25 text-emerald-50 hover:border-emerald-300/80 hover:bg-emerald-600/30 shadow-[0_6px_16px_rgba(5,46,22,0.35)]",
        else:
          "border-zinc-700/70 bg-zinc-900/80 text-zinc-300 hover:border-zinc-500/90 hover:bg-zinc-800/90 shadow-[inset_0_1px_0_rgba(255,255,255,0.03),inset_0_0_0_1px_rgba(0,0,0,0.35)]"
      ),
      if(selected?,
        do:
          if(assigned?,
            do:
              "border-2 border-emerald-300/90 bg-emerald-600/35 text-emerald-50 shadow-[0_0_0_1px_rgba(110,231,183,0.45),0_8px_20px_rgba(6,78,59,0.35)]",
            else:
              "border-2 border-zinc-500/90 bg-zinc-800/95 text-zinc-100 shadow-[0_0_0_1px_rgba(161,161,170,0.25),0_8px_20px_rgba(9,9,11,0.35)]"
          ),
        else: ""
      )
    ]
  end

  defp play_notes_for_3s(socket, notes, source_label \\ "Previewing chord") do
    final_notes = Enum.filter(notes, &is_integer/1)

    cond do
      final_notes == [] ->
        {:noreply, put_flash(socket, :error, "No notes to play")}

      true ->
        socket = stop_preview(socket)

        channels = Mensch.Midi.Connection.member_channels()

        note_channels =
          final_notes
          |> Enum.uniq()
          |> Enum.take(length(channels))
          |> Enum.zip(channels)

        if note_channels == [] do
          {:noreply, put_flash(socket, :error, "No MIDI channels available")}
        else
          on_messages =
            Enum.flat_map(note_channels, fn {note, channel} ->
              [
                <<0x90 + channel, note, 100>>,
                <<0xD0 + channel, 100>>,
                <<0xE0 + channel, 0, 64>>,
                <<0xB0 + channel, 74, 64>>
              ]
            end)

          case Mensch.Midi.Connection.send_messages(on_messages) do
            :ok ->
              stop_ref = make_ref()
              Process.send_after(self(), {:stop_preview_notes, stop_ref}, 3000)

              {:noreply,
               socket
               |> assign(:keyboard_active_notes, Enum.uniq(final_notes))
               |> assign(:keyboard_source, source_label)
               |> assign(:preview_note_channels, note_channels)
               |> assign(:preview_stop_ref, stop_ref)}

            {:error, :disconnected} ->
              {:noreply, put_flash(socket, :error, "MIDI is disconnected")}
          end
        end
    end
  end

  defp stop_preview(socket) do
    off_messages =
      Enum.flat_map(socket.assigns.preview_note_channels, fn {note, channel} ->
        [
          <<0x80 + channel, note, 0>>,
          <<0x90 + channel, note, 0>>,
          <<0xD0 + channel, 0>>,
          <<0xB0 + channel, 74, 0>>
        ]
      end)

    if off_messages != [] do
      _ = Mensch.Midi.Connection.send_messages(off_messages)
    end

    socket
    |> assign(:preview_note_channels, [])
    |> assign(:preview_stop_ref, nil)
    |> assign_keyboard_from_selected_pad()
  end

  defp assign_keyboard_from_selected_pad(socket) do
    case socket.assigns do
      %{record: %{chord_matrix: %ChordMatrix{} = chord_matrix}, selected_pad: {row, col}} ->
        case ChordMatrix.assignment_at(chord_matrix, row, col) do
          %{chord_spec: %ChordSpec{} = chord_spec} ->
            socket
            |> assign(:keyboard_active_notes, Resolver.resolve(chord_spec))
            |> assign(:keyboard_source, "Selected pad: #{ChordSpec.symbol_label(chord_spec)}")

          _ ->
            socket
            |> assign(:keyboard_active_notes, [])
            |> assign(:keyboard_source, "Selected pad is empty")
        end

      _ ->
        socket
        |> assign(:keyboard_active_notes, [])
        |> assign(:keyboard_source, "No chord selected")
    end
  end

  defp piano_keys(active_notes) when is_list(active_notes) do
    FullPianoKeyboard.key_maps(active_notes: active_notes)
  end

  defp piano_keys(_active_notes), do: []

  defp format_timestamp(value) when is_binary(value) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(value) do
      Calendar.strftime(datetime, "%b %-d, %Y %-I:%M:%S %p UTC")
    else
      _ -> value
    end
  end

  defp format_timestamp(value), do: to_string(value)
end
