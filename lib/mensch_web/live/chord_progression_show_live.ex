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
          <h3 class="mb-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
            Chords List
          </h3>
          <div class="space-y-4">
            <div
              :for={card <- @chord_cards}
              class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
            >
              <div class="flex flex-col gap-3 md:flex-row md:items-start">
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
