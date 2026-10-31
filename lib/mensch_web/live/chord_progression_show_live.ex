defmodule MenschWeb.ChordProgressionShowLive do
  use MenschWeb, :live_view

  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver
  alias MenschWeb.FullPianoKeyboard

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:preview_note_channels, [])
      |> assign(:preview_stop_ref, nil)
      |> assign(:selected_chord_indices, [])
      |> assign(:save_selected_modal_open, false)
      |> assign(:save_selected_name, "")
      |> assign(:save_selected_description, "")

    case ChordProgressions.fetch_progression(id) do
      {:ok, record} ->
        progression = record.progression

        {:ok,
         socket
         |> assign(:record, record)
         |> assign(:progression, progression)
         |> assign(:chord_cards, build_chord_cards(progression.chords))
         |> assign(:error_message, nil)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:record, nil)
         |> assign(:progression, nil)
         |> assign(:chord_cards, [])
         |> assign(:error_message, "Progression not found")}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(:record, nil)
         |> assign(:progression, nil)
         |> assign(:chord_cards, [])
         |> assign(:error_message, "Failed to load progression: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("play_chord", %{"index" => index}, socket) do
    chord =
      case Integer.parse(to_string(index)) do
        {parsed, ""} ->
          socket.assigns.progression
          |> Map.get(:chords, [])
          |> Enum.at(parsed)

        _ ->
          nil
      end

    case chord do
      %ChordSpec{} = chord_spec ->
        notes = Resolver.resolve(chord_spec)
        play_notes_for_3s(socket, notes)

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid chord selection")}
    end
  end

  @impl true
  def handle_event("toggle_chord_selection", %{"selected_index" => index} = params, socket) do
    selected = Map.get(params, "selected", "false") == "true"

    selected_indices =
      case Integer.parse(index) do
        {parsed_index, ""} when parsed_index >= 0 ->
          if selected do
            append_unique_index(socket.assigns.selected_chord_indices, parsed_index)
          else
            Enum.reject(socket.assigns.selected_chord_indices, &(&1 == parsed_index))
          end

        _ ->
          socket.assigns.selected_chord_indices
      end

    {:noreply, assign(socket, :selected_chord_indices, selected_indices)}
  end

  @impl true
  def handle_event("open_save_selected_modal", _params, socket) do
    if length(socket.assigns.selected_chord_indices) == 0 do
      {:noreply, put_flash(socket, :error, "Select at least one chord")}
    else
      default_name = default_selected_save_name(socket.assigns.progression)

      {:noreply,
       socket
       |> assign(:save_selected_modal_open, true)
       |> assign(:save_selected_name, default_name)
       |> assign(:save_selected_description, "")}
    end
  end

  @impl true
  def handle_event("close_save_selected_modal", _params, socket) do
    {:noreply, assign(socket, :save_selected_modal_open, false)}
  end

  @impl true
  def handle_event("set_save_selected_form", %{"selection" => params}, socket) do
    {:noreply,
     socket
     |> assign(:save_selected_name, Map.get(params, "name", ""))
     |> assign(:save_selected_description, Map.get(params, "description", ""))}
  end

  @impl true
  def handle_event("move_selected_chord", %{"index" => index, "direction" => direction}, socket) do
    selected_indices =
      case Integer.parse(index) do
        {parsed_index, ""} ->
          case direction do
            "up" -> move_item(socket.assigns.selected_chord_indices, parsed_index, -1)
            "down" -> move_item(socket.assigns.selected_chord_indices, parsed_index, 1)
            _ -> socket.assigns.selected_chord_indices
          end

        _ ->
          socket.assigns.selected_chord_indices
      end

    {:noreply, assign(socket, :selected_chord_indices, selected_indices)}
  end

  @impl true
  def handle_event("remove_selected_chord", %{"index" => index}, socket) do
    selected_indices =
      case Integer.parse(index) do
        {parsed_index, ""} ->
          Enum.reject(socket.assigns.selected_chord_indices, &(&1 == parsed_index))

        _ ->
          socket.assigns.selected_chord_indices
      end

    {:noreply, assign(socket, :selected_chord_indices, selected_indices)}
  end

  @impl true
  def handle_event("save_selected_as_new_progression", %{"selection" => params}, socket) do
    name = Map.get(params, "name", socket.assigns.save_selected_name)
    description = Map.get(params, "description", socket.assigns.save_selected_description)

    selected_chords = selected_chords(socket)

    cond do
      selected_chords == [] ->
        {:noreply, put_flash(socket, :error, "No chords selected")}

      true ->
        case ChordProgressions.create_progression(
               name,
               description,
               selected_chords
             ) do
          {:ok, record} ->
            {:noreply,
             socket
             |> assign(:save_selected_modal_open, false)
             |> assign(:selected_chord_indices, [])
             |> put_flash(:info, "New progression created from selected chords")
             |> push_navigate(to: ~p"/chord-progressions/#{record.id}")}

          {:error, :name_required} ->
            {:noreply, put_flash(socket, :error, "Name is required")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("save_selected_as_new_progression", _params, socket) do
    {:noreply, put_flash(socket, :error, "Invalid form submission")}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
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
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:progression}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <div class="flex items-center justify-between gap-3">
          <.page_heading
            title={if(@progression, do: @progression.name, else: "Chord Progression")}
            subtitle={if(@progression, do: @progression.description, else: "")}
          />
          <.link
            navigate={~p"/chord-progressions"}
            class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
          >
            Back to List
          </.link>
        </div>

        <div :if={@error_message} class="rounded-sm border border-rose-500/40 bg-rose-950/30 p-3">
          <p class="font-mono text-xs text-rose-200">{@error_message}</p>
        </div>

        <div
          :if={@progression}
          class="ui-radius-table rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3"
        >
          <div class="mb-3 flex flex-wrap items-center justify-end gap-2">
            <button
              type="button"
              phx-click="open_save_selected_modal"
              disabled={length(@selected_chord_indices) == 0}
              class="rounded-sm border border-sky-300 bg-sky-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-sky-100 transition-colors duration-150 enabled:hover:bg-sky-400/30 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Save Selected as New Progression
            </button>
          </div>

          <h3 class="mb-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
            Chords List
          </h3>
          <div class="space-y-4">
            <div
              :for={card <- @chord_cards}
              class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
            >
              <div class="flex flex-col gap-3 md:flex-row md:items-start">
                <form
                  id={"selected-chord-form-#{card.index}"}
                  phx-change="toggle_chord_selection"
                  class="pt-1"
                >
                  <input type="hidden" name="selected_index" value={card.index} />
                  <input type="hidden" name="selected" value="false" />
                  <input
                    type="checkbox"
                    name="selected"
                    value="true"
                    checked={card.index in @selected_chord_indices}
                    class="h-4 w-4 cursor-pointer rounded border-zinc-500 bg-zinc-900 text-sky-400 focus:ring-sky-400"
                  />
                </form>

                <button
                  type="button"
                  phx-click="play_chord"
                  phx-value-index={card.index}
                  class="w-56 shrink-0 rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-2 text-center font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
                >
                  {card.degree} · {card.symbol}
                </button>

                <div class="min-w-0 flex-1 md:max-w-4xl">
                  <div class="rounded-md border border-zinc-700/70 bg-zinc-950 p-2">
                    <FullPianoKeyboard.keyboard
                      id={"saved-progression-keyboard-#{card.index}"}
                      keys={card.keyboard_keys}
                      height_class="h-28"
                      show_bottom_lane={false}
                      color_mode={:dark}
                    />
                  </div>

                  <p class="mt-2 font-mono text-[11px] text-zinc-400">{card.named_notes}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%= if @save_selected_modal_open do %>
          <div class="fixed inset-0 z-40 bg-black/70" phx-click="close_save_selected_modal"></div>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
            <div
              class="w-full max-w-2xl rounded-sm border border-zinc-700 bg-zinc-950 p-5 shadow-2xl"
              phx-click-away="close_save_selected_modal"
            >
              <div class="mb-4 flex items-start justify-between gap-4">
                <div>
                  <h2 class="font-mono text-sm text-zinc-100">Save Selected Chords</h2>
                  <p class="mt-1 font-mono text-xs text-zinc-400">
                    Reorder selected chords to define the final progression sequence.
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="close_save_selected_modal"
                  class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-xs text-zinc-300 hover:border-zinc-500"
                >
                  Close
                </button>
              </div>

              <.form
                for={%{}}
                as={:selection}
                phx-change="set_save_selected_form"
                phx-submit="save_selected_as_new_progression"
                id="save-selected-chords-form"
                class="space-y-4"
              >
                <div class="grid gap-3 md:grid-cols-2">
                  <div class="space-y-1">
                    <label class="font-mono text-xs text-zinc-300" for="selected-save-name">Name</label>
                    <input
                      id="selected-save-name"
                      name="selection[name]"
                      value={@save_selected_name}
                      required
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900 px-3 py-2 font-mono text-xs text-zinc-100 focus:border-sky-400 focus:outline-none"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="font-mono text-xs text-zinc-300" for="selected-save-description">
                      Description
                    </label>
                    <input
                      id="selected-save-description"
                      name="selection[description]"
                      value={@save_selected_description}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900 px-3 py-2 font-mono text-xs text-zinc-100 focus:border-sky-400 focus:outline-none"
                    />
                  </div>
                </div>

                <div class="space-y-2 rounded-sm border border-zinc-700/70 bg-black/30 p-3">
                  <p class="font-mono text-xs text-zinc-400">Order of selected chords</p>

                  <div class="space-y-2">
                    <%= for {selected_index, position} <- Enum.with_index(@selected_chord_indices) do %>
                      <% card = card_by_index(@chord_cards, selected_index) %>
                      <%= if card do %>
                        <div class="flex items-center gap-2 rounded-sm border border-zinc-700 bg-zinc-950/70 p-2">
                          <span class="w-6 text-center font-mono text-xs text-zinc-400">{position + 1}</span>
                          <div class="min-w-0 flex-1">
                            <p class="truncate font-mono text-xs text-zinc-100">
                              {card.degree} · {card.symbol}
                            </p>
                            <p class="font-mono text-[11px] text-zinc-500">{card.named_notes}</p>
                          </div>
                          <div class="flex items-center gap-1">
                            <button
                              type="button"
                              phx-click="move_selected_chord"
                              phx-value-index={selected_index}
                              phx-value-direction="up"
                              disabled={position == 0}
                              class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-[11px] text-zinc-200 enabled:hover:border-zinc-500 disabled:opacity-40"
                            >
                              Up
                            </button>
                            <button
                              type="button"
                              phx-click="move_selected_chord"
                              phx-value-index={selected_index}
                              phx-value-direction="down"
                              disabled={position == length(@selected_chord_indices) - 1}
                              class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-[11px] text-zinc-200 enabled:hover:border-zinc-500 disabled:opacity-40"
                            >
                              Down
                            </button>
                            <button
                              type="button"
                              phx-click="remove_selected_chord"
                              phx-value-index={selected_index}
                              class="rounded-sm border border-rose-800/80 px-2 py-1 font-mono text-[11px] text-rose-200 hover:border-rose-700"
                            >
                              Remove
                            </button>
                          </div>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center justify-end gap-2">
                  <button
                    type="button"
                    phx-click="close_save_selected_modal"
                    class="rounded-sm border border-zinc-600 px-3 py-1.5 font-mono text-xs text-zinc-200 hover:border-zinc-500"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={length(@selected_chord_indices) == 0}
                    class="rounded-sm border border-sky-300 bg-sky-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-sky-100 transition-colors duration-150 enabled:hover:bg-sky-400/30 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Create New Progression
                  </button>
                </div>
              </.form>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp degree_label(degree) do
    case degree do
      1 -> "I"
      2 -> "II"
      3 -> "III"
      4 -> "IV"
      5 -> "V"
      6 -> "VI"
      7 -> "VII"
      _ -> Integer.to_string(degree)
    end
  end

  defp build_chord_cards(chords) when is_list(chords) do
    chords
    |> Enum.with_index()
    |> Enum.map(fn {chord_spec, index} ->
      notes = Resolver.resolve(chord_spec)

      %{
        index: index,
        degree: degree_label(index + 1),
        symbol: ChordSpec.symbol_label(chord_spec),
        named_notes: join_named_notes(notes),
        keyboard_keys: piano_keys(notes)
      }
    end)
  end

  defp build_chord_cards(_chords), do: []

  defp join_named_notes(notes) do
    notes
    |> Enum.map(fn note ->
      {name, octave} = ChordSpec.note_name(note)
      "#{ChordSpec.root_label(name)}#{octave}"
    end)
    |> Enum.join("  ")
  end

  defp piano_keys(active_notes) when is_list(active_notes) do
    FullPianoKeyboard.key_maps(active_notes: active_notes)
  end

  defp piano_keys(_active_notes), do: []

  defp append_unique_index(indices, index) do
    if index in indices, do: indices, else: indices ++ [index]
  end

  defp card_by_index(cards, index) do
    Enum.find(cards, &(&1.index == index))
  end

  defp move_item(indices, index, delta) do
    with current_position when is_integer(current_position) <-
           Enum.find_index(indices, &(&1 == index)),
         target_position <- current_position + delta,
         true <- target_position >= 0 and target_position < length(indices) do
      value = Enum.at(indices, current_position)

      indices
      |> List.delete_at(current_position)
      |> List.insert_at(target_position, value)
    else
      _ -> indices
    end
  end

  defp selected_chords(socket) do
    chords = socket.assigns.progression |> Map.get(:chords, [])

    socket.assigns.selected_chord_indices
    |> Enum.map(&Enum.at(chords, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp default_selected_save_name(nil), do: "Selected Chords Progression"

  defp default_selected_save_name(progression) do
    name = progression |> Map.get(:name, "Chord Progression") |> String.trim()

    if name == "" do
      "Selected Chords Progression"
    else
      "#{name} (selection)"
    end
  end

  defp play_notes_for_3s(socket, notes) do
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
  end
end
