defmodule MenschWeb.HomeLive do
  @moduledoc """
  Minimal UI: RENDER precomputes the full MPE performance for a
  hardcoded C4 maj7 chord (see `Mensch.PerformanceAssembler`), showing its pressure/
  slide/bend curves as line charts. PLAY then dispatches that
  precomputed data in real time to the connected MIDI output (e.g. an
  Osmose); STOP silences it immediately.
  """

  use MenschWeb, :live_view

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Player
  alias Mensch.PerformanceAssembler
  alias Mensch.SampleDb
  alias Mensch.SampleContext
  alias Mensch.TimelineContext
  alias MenschWeb.HomeLive.DetailPanelComponent
  alias MenschWeb.HomeLive.SampleEntryDetailsModalComponent

  @refresh_interval_ms 33
  @chart_colors ["#FF7A1A", "#2FD5C8", "#75B8FF", "#B188FF", "#9BF25A", "#FF5D8F"]
  @inactive_note_color "rgba(109, 122, 140, 0.28)"
  @sharp_note_display %{
    c: "C",
    c_sharp: "C♯",
    d: "D",
    d_sharp: "D♯",
    e: "E",
    f: "F",
    f_sharp: "F♯",
    g: "G",
    g_sharp: "G♯",
    a: "A",
    a_sharp: "A♯",
    b: "B"
  }
  @flat_note_display %{
    c: "C",
    c_sharp: "D♭",
    d: "D",
    d_sharp: "E♭",
    e: "E",
    f: "F",
    f_sharp: "G♭",
    g: "G",
    g_sharp: "A♭",
    a: "A",
    a_sharp: "B♭",
    b: "B"
  }

  @impl true
  def mount(_params, _session, socket) do
    samples = SampleDb.default_samples()

    active_sample_index =
      Enum.find_index(samples, fn sample ->
        Map.get(sample, :folder) == "Dynamic Voicing"
      end) || 0

    active_sample = Enum.at(samples, active_sample_index, %{})
    sample_entries = Map.get(active_sample, :sample_entries, [])

    sample_context =
      Map.get(active_sample, :sample_context, SampleDb.default_sample_context())

    render_data = PerformanceAssembler.generate_sample(sample_entries, sample_context)

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:render_data, render_data)
      |> assign(:player_status, Player.status())
      |> assign(:play_started_at, nil)
      |> assign(:playing_duration_ms, nil)
      |> assign(:playhead_pct, nil)
      |> assign(:playback_ref, nil)
      |> assign(:pressure_chart, [])
      |> assign(:slide_chart, [])
      |> assign(:bend_chart, [])
      |> assign(:debug_rows, [])
      |> assign(:note_matrix, [])
      |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
      |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})
      |> assign(:samples, samples)
      |> assign(:sample_folders, build_sample_folders(samples))
      |> assign(:active_sample_index, active_sample_index)
      |> assign(:sample_entries, sample_entries)
      |> assign(:active_chord_indices, all_chord_indices(sample_entries))
      |> assign(:sample_context, sample_context)
      |> assign(
        :sample_timeline_static,
        sample_timeline_static_model(sample_entries, sample_context)
      )
      |> assign(:render_scope, :full_sample)
      |> assign(:loop_full_sample, false)
      |> assign(:show_detail_panel, true)
      |> assign(:show_samples_modal, false)
      |> assign(:selected_sample_entry_index, nil)
      |> assign(:selected_note_key, nil)
      |> assign(:debug_on_filter, :no_filter)
      |> assign(:debug_off_filter, :no_filter)
      |> assign(:manual_stop, false)
      |> assign_detail_content()

    {:ok, socket}
  end

  @impl true
  def handle_event("play_full_sample", _params, socket) do
    {:noreply,
     socket
     |> assign(:render_scope, :full_sample)
     |> assign(:selected_note_key, nil)
     |> assign_detail_content()
     |> assign(:manual_stop, false)
     |> start_active_playback()}
  end

  def handle_event("toggle_loop_full_sample", _params, socket) do
    {:noreply, update(socket, :loop_full_sample, &(!&1))}
  end

  def handle_event("toggle_detail_panel", _params, socket) do
    {:noreply, update(socket, :show_detail_panel, &(!&1))}
  end

  def handle_event("open_samples_modal", _params, socket) do
    {:noreply, assign(socket, :show_samples_modal, true)}
  end

  def handle_event("close_samples_modal", _params, socket) do
    {:noreply, assign(socket, :show_samples_modal, false)}
  end

  def handle_event("activate_sample", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, ""} ->
        case Enum.at(socket.assigns.samples, index) do
          %{sample_entries: sample_entries, sample_context: sample_context} ->
            Player.stop()
            render_data = PerformanceAssembler.generate_sample(sample_entries, sample_context)

            {:noreply,
             socket
             |> assign(:active_sample_index, index)
             |> assign(:sample_entries, sample_entries)
             |> assign(:active_chord_indices, all_chord_indices(sample_entries))
             |> assign(:sample_context, sample_context)
             |> assign(
               :sample_timeline_static,
               sample_timeline_static_model(sample_entries, sample_context)
             )
             |> assign(:render_data, render_data)
             |> assign(:render_scope, :full_sample)
             |> assign(:selected_sample_entry_index, nil)
             |> assign(:show_samples_modal, false)
             |> assign(:player_status, Player.status())
             |> clear_playback_state(true)
             |> assign(:selected_note_key, nil)
             |> assign_detail_content()}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_note_focus", params, socket) do
    note_str = Map.get(params, "note", "")
    channel_str = Map.get(params, "channel", "")

    with {note, ""} <- Integer.parse(to_string(note_str)),
         {channel, ""} <- Integer.parse(to_string(channel_str)) do
      selected_note_key = {channel, note}

      next_selected =
        if socket.assigns.selected_note_key == selected_note_key do
          nil
        else
          selected_note_key
        end

      {:noreply, socket |> assign(:selected_note_key, next_selected) |> assign_detail_content()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_note_focus", _params, socket) do
    {:noreply, socket |> assign(:selected_note_key, nil) |> assign_detail_content()}
  end

  def handle_event("toggle_active_chord", %{"index" => index_str}, socket) do
    next_active_indices =
      case Integer.parse(index_str) do
        {index, ""} when index >= 0 and index < length(socket.assigns.sample_entries) ->
          toggle_chord_index(socket.assigns.active_chord_indices, index)

        _ ->
          socket.assigns.active_chord_indices
      end

    {:noreply,
     socket
     |> assign(:active_chord_indices, next_active_indices)
     |> assign_detail_content()}
  end

  def handle_event("open_sample_entry_details", %{"index" => index_str}, socket) do
    selected_sample_entry_index =
      case Integer.parse(index_str) do
        {index, ""} when index >= 0 and index < length(socket.assigns.sample_entries) -> index
        _ -> nil
      end

    {:noreply, assign(socket, :selected_sample_entry_index, selected_sample_entry_index)}
  end

  def handle_event("close_sample_entry_details", _params, socket) do
    {:noreply, assign(socket, :selected_sample_entry_index, nil)}
  end

  def handle_event("play", _params, %{assigns: %{render_data: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("play", _params, socket) do
    {:noreply, socket |> assign(:manual_stop, false) |> start_active_playback()}
  end

  def handle_event("stop", _params, socket) do
    Player.stop()

    socket =
      socket
      |> assign(:player_status, Player.status())
      |> clear_playback_state(true)

    {:noreply, socket}
  end

  def handle_event("panic_all_notes", _params, socket) do
    Player.panic()

    socket =
      socket
      |> assign(:player_status, Player.status())
      |> clear_playback_state(true)

    {:noreply, socket}
  end

  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  def handle_event("set_debug_rows_filters", params, socket) do
    on_filter = normalize_bool_filter(Map.get(params, "on_filter"))
    off_filter = normalize_bool_filter(Map.get(params, "off_filter"))

    {:noreply,
     socket
     |> assign(:debug_on_filter, on_filter)
     |> assign(:debug_off_filter, off_filter)
     |> assign_detail_content()}
  end

  @impl true
  def handle_info({:refresh_player, refresh_ref}, socket) do
    if socket.assigns.playback_ref != refresh_ref do
      {:noreply, socket}
    else
      status = Player.status()

      cond do
        status == :playing ->
          socket =
            socket
            |> assign(:player_status, status)
            |> assign(
              :playhead_pct,
              playhead_pct(
                status,
                socket.assigns.play_started_at,
                socket.assigns.playing_duration_ms
              )
            )

          Process.send_after(self(), {:refresh_player, refresh_ref}, @refresh_interval_ms)
          {:noreply, socket}

        loop_full_sample?(socket) ->
          {:noreply, socket |> assign(:manual_stop, false) |> start_active_playback()}

        true ->
          {:noreply,
           socket
           |> assign(:player_status, status)
           |> clear_playback_state(false)}
      end
    end
  end

  def handle_info({:playback_done, playback_ref}, socket) do
    if socket.assigns.playback_ref != playback_ref do
      {:noreply, socket}
    else
      status = Player.status()

      cond do
        status == :playing ->
          {:noreply, socket}

        loop_full_sample?(socket) ->
          {:noreply, socket |> assign(:manual_stop, false) |> start_active_playback()}

        true ->
          {:noreply,
           socket
           |> assign(:player_status, status)
           |> clear_playback_state(false)}
      end
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :sample_timeline,
        sample_timeline_with_playhead(
          assigns.sample_timeline_static,
          assigns.render_scope,
          assigns.playhead_pct,
          assigns.active_chord_indices
        )
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} show_samples_button={true}>
      <div class="w-full">
        <div id="render-section" class="min-w-0 space-y-4">
          <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div class="space-y-1">
              <div class="font-mono text-xl text-zinc-100 md:text-2xl">
                {active_sample_name(@samples, @active_sample_index)}
              </div>

              <div class="font-mono text-[11px] text-zinc-300">
                {sample_context_label(@sample_context)} · {sample_duration_label(
                  @sample_entries,
                  @sample_context
                )}
              </div>
            </div>

            <div class="ui-gap-control flex items-center justify-end">
              <div class="ui-radius-btn inline-flex h-9 items-center overflow-hidden border border-zinc-600/80">
                <button
                  type="button"
                  id="toggle-loop-full-sample"
                  phx-click="toggle_loop_full_sample"
                  aria-label="Toggle loop"
                  title={if @loop_full_sample, do: "Loop on", else: "Loop off"}
                  aria-pressed={@loop_full_sample}
                  class={[
                    "flex h-9 w-9 items-center justify-center transition-colors duration-150",
                    (@loop_full_sample &&
                       "bg-[#ff7a1a]/20 text-[#ffd8be]") ||
                      "bg-transparent text-zinc-300 hover:bg-[#ff7a1a]/12 hover:text-[#ffd8be]"
                  ]}
                >
                  <.icon
                    name="hero-arrow-path"
                    class={["size-4", @loop_full_sample && "motion-safe:animate-spin"]}
                  />
                </button>
                <button
                  type="button"
                  id="play-full-sample"
                  aria-label="Play full sample"
                  title="Play"
                  phx-click="play_full_sample"
                  class={[
                    "flex h-9 w-9 items-center justify-center border-l border-zinc-600/80 transition-colors duration-150",
                    (@player_status == :playing &&
                       "bg-[#9bf25a]/20 text-[#dfffc7]") ||
                      "bg-transparent text-[#bff58f] hover:bg-[#9bf25a]/12 hover:text-[#dfffc7]"
                  ]}
                >
                  <.icon name="hero-play-solid" class="size-4" />
                </button>
                <button
                  type="button"
                  id="stop-full-sample"
                  aria-label="Stop full sample"
                  title="Stop"
                  phx-click="stop"
                  class={[
                    "flex h-9 w-9 items-center justify-center border-l border-zinc-600/80 transition-colors duration-150",
                    (@player_status != :playing &&
                       "bg-white/15 text-white") ||
                      "bg-transparent text-white/90 hover:bg-white/10 hover:text-white"
                  ]}
                >
                  <.icon name="hero-stop-solid" class="size-4" />
                </button>
                <button
                  type="button"
                  id="panic-all-notes"
                  aria-label="Panic stop all notes"
                  title="Panic Stop"
                  phx-click="panic_all_notes"
                  class="flex h-9 w-9 items-center justify-center border-l border-zinc-600/80 bg-transparent text-[#ff84aa] transition-colors duration-150 hover:bg-[#ff5d8f]/12 hover:text-[#ffc0d4]"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                </button>
              </div>

              <div class="ui-radius-btn inline-flex h-9 items-center overflow-hidden border border-zinc-600/80">
                <.link
                  id="download-bitwig-mpe-midi"
                  href={~p"/exports/sample/#{@active_sample_index}/bitwig-mpe.mid"}
                  aria-label="Download Bitwig MIDI"
                  title="Bitwig MIDI"
                  class="flex h-9 w-9 items-center justify-center text-zinc-300 transition-colors duration-150 hover:bg-[#2fd5c8]/12 hover:text-[#a6f6ef]"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" />
                </.link>
                <.link
                  id="download-mpe-report"
                  href={~p"/exports/sample/#{@active_sample_index}/mpe-events.txt"}
                  aria-label="Download event report"
                  title="Event Report"
                  class="flex h-9 w-9 items-center justify-center border-l border-zinc-600/80 text-zinc-300 transition-colors duration-150 hover:bg-[#2fd5c8]/12 hover:text-[#a6f6ef]"
                >
                  <.icon name="hero-document-text" class="size-4" />
                </.link>
              </div>
            </div>
          </div>

          <div class="ui-radius-table overflow-x-auto border border-zinc-700/60">
            <table class="w-full min-w-[760px] text-left font-mono text-[10px] sm:text-[11px]">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-1.5 py-1.5 font-normal">ChordSpec</th>
                  <th class="px-1.5 py-1.5 font-normal">Machine</th>
                  <th class="px-1.5 py-1.5 font-normal">Start</th>
                  <th class="px-1.5 py-1.5 font-normal">Duration</th>
                  <th class="px-1.5 py-1.5 font-normal text-center">Active</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{entry, index} <- Enum.with_index(@sample_entries)}
                  class="group text-zinc-200 transition-colors duration-150 hover:bg-[#2fd5c8]/12"
                >
                  <td
                    class="cursor-pointer px-1.5 py-1.5 text-zinc-100"
                    phx-click="open_sample_entry_details"
                    phx-value-index={index}
                  >
                    <div class="flex items-center gap-2">
                      <span
                        class="inline-block size-2.5 rounded-full"
                        style={entry_color_dot_style(index)}
                      ></span>
                      <span>{table_chord_label(entry.chord_spec)}</span>
                    </div>
                  </td>
                  <td
                    class="cursor-pointer px-1.5 py-1.5"
                    phx-click="open_sample_entry_details"
                    phx-value-index={index}
                  >
                    <div class="flex items-center gap-1.5">
                      <.icon name={machine_icon_name(entry.machine)} class="size-3.5 text-zinc-400" />
                      <span>{machine_label(entry.machine)}</span>
                    </div>
                  </td>
                  <td
                    class="cursor-pointer px-1.5 py-1.5 align-middle"
                    phx-click="open_sample_entry_details"
                    phx-value-index={index}
                  >
                    <div class="leading-tight text-zinc-100">
                      {table_start_label(@sample_context, entry.timeline_context.start_beat)}
                    </div>
                  </td>
                  <td
                    class="cursor-pointer px-1.5 py-1.5 align-middle"
                    phx-click="open_sample_entry_details"
                    phx-value-index={index}
                  >
                    <div class="leading-tight text-zinc-100">
                      {table_duration_label(@sample_context, entry.timeline_context)}
                    </div>
                  </td>
                  <td class="px-1.5 py-1.5 text-center">
                    <button
                      type="button"
                      phx-click="toggle_active_chord"
                      phx-value-index={index}
                      aria-label={"Toggle chord #{index}"}
                      aria-pressed={chord_active?(@active_chord_indices, index)}
                      class={[
                        "inline-flex size-5 items-center justify-center rounded-sm border transition-colors duration-150",
                        chord_active?(@active_chord_indices, index) &&
                          "border-[#2fd5c8] bg-[#2fd5c8]/20 text-[#a6f6ef]",
                        !chord_active?(@active_chord_indices, index) &&
                          "border-zinc-600 text-zinc-400 hover:border-[#2fd5c8] hover:text-[#a6f6ef]"
                      ]}
                    >
                      <.icon
                        name={
                          if chord_active?(@active_chord_indices, index),
                            do: "hero-check",
                            else: "hero-minus"
                        }
                        class="size-3"
                      />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.sample_timeline model={@sample_timeline} />

          <div class="-mb-2 flex items-center justify-center">
            <button
              type="button"
              id="toggle-detail-panel"
              phx-click="toggle_detail_panel"
              aria-label="Toggle detail charts"
              aria-pressed={@show_detail_panel}
              class="inline-flex items-center gap-1.5 px-2 py-1 font-mono text-[10px] uppercase tracking-wide text-zinc-500 transition-colors duration-150 hover:text-zinc-300"
            >
              <.icon
                name={if @show_detail_panel, do: "hero-chevron-up", else: "hero-chevron-down"}
                class="size-3.5"
              />
              <span>Details</span>
            </button>
          </div>

          <.live_component
            :if={@render_data && @show_detail_panel}
            module={DetailPanelComponent}
            id="detail-panel"
            render_data={@render_data}
            selected_note_key={@selected_note_key}
            selected_note_label={selected_note_label(@selected_note_key)}
            note_matrix={@note_matrix}
            note_matrix_grid={@note_matrix_grid}
            timeline_start_label={local_timeline_start_label()}
            timeline_end_label={local_timeline_end_label(@sample_context, @render_data.duration_ms)}
            pressure_chart={@pressure_chart}
            slide_chart={@slide_chart}
            bend_chart={@bend_chart}
            chart_grid={@chart_grid}
            debug_rows={@debug_rows}
            debug_on_filter={@debug_on_filter}
            debug_off_filter={@debug_off_filter}
          />

          <.live_component
            :if={not is_nil(@selected_sample_entry_index)}
            module={SampleEntryDetailsModalComponent}
            id="sample-entry-details-modal"
            sample_entry={selected_sample_entry(@sample_entries, @selected_sample_entry_index)}
            sample_entry_index={@selected_sample_entry_index}
            sample_context={@sample_context}
          />
        </div>

        <div
          :if={@show_samples_modal}
          id="samples-modal"
          class="fixed inset-0 z-40 flex items-start justify-end bg-black/45 p-3 sm:p-4"
        >
          <button
            type="button"
            aria-label="Close sample library"
            phx-click="close_samples_modal"
            class="absolute inset-0"
          ></button>

          <div class="ui-radius-modal relative w-full max-w-md border border-zinc-700/70 bg-zinc-950/95 p-4 shadow-2xl">
            <div class="mb-3 flex items-center justify-between">
              <div class="flex items-center gap-2 text-[11px] uppercase tracking-wide text-zinc-300">
                <.icon name="hero-queue-list" class="size-4" /> Sample Library
              </div>
              <button
                type="button"
                phx-click="close_samples_modal"
                class="ui-radius-btn flex size-8 items-center justify-center border border-zinc-700 text-zinc-300 transition-colors duration-150 hover:border-zinc-500 hover:text-white"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div class="max-h-[78vh] space-y-4 overflow-y-auto pr-1">
              <div :for={folder <- @sample_folders} class="space-y-2">
                <div class="text-[10px] uppercase tracking-wide text-zinc-500">{folder.name}</div>

                <button
                  :for={{sample, index} <- folder.samples}
                  type="button"
                  id={"activate-sample-#{index}"}
                  phx-click="activate_sample"
                  phx-value-index={index}
                  class={[
                    "ui-radius-btn w-full space-y-1 border px-3 py-2 text-left transition-colors duration-150",
                    (@active_sample_index == index &&
                       "border-[#2fd5c8] bg-[#2fd5c8]/10") ||
                      "border-zinc-700/80 bg-zinc-950/55 hover:border-[#2fd5c8]/80"
                  ]}
                >
                  <div class="font-mono text-[12px] text-zinc-100">
                    {Map.get(sample, :name, "Unnamed")}
                  </div>
                  <div class="font-mono text-[10px] text-zinc-400">
                    {Map.get(sample.sample_context, :bpm, 0)} bpm · {elem(
                      sample.sample_context.time_signature,
                      0
                    )}/{elem(sample.sample_context.time_signature, 1)} · {sample_duration_label(
                      Map.get(sample, :sample_entries, []),
                      Map.get(sample, :sample_context, @sample_context)
                    )}
                  </div>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :model, :map, required: true

  defp sample_timeline(assigns) do
    ~H"""
    <div id="sample-timeline" class="space-y-2 bg-zinc-950/70 py-3">
      <div class="flex items-center justify-between font-mono text-[11px] text-zinc-400">
        <span class="uppercase tracking-wide">Timeline</span>
        <span>
          {@model.row_count} rows · {@model.bar_count} bars · {@model.beat_count} beats · {@model.total_mbeats} mbeats
        </span>
      </div>

      <svg
        viewBox={"0 0 #{@model.svg_width} #{@model.svg_height}"}
        class="w-full bg-zinc-950/80"
      >
        <line
          :for={x <- @model.subbeat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="var(--ui-grid-subbeat)"
          stroke-opacity="0.3"
          stroke-width="1"
        />
        <line
          :for={x <- @model.beat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="var(--ui-grid-beat)"
          stroke-opacity="0.35"
          stroke-width="1"
        />
        <line
          :for={{x, bar_number} <- @model.bar_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="var(--ui-grid-bar)"
          stroke-opacity="0.4"
          stroke-width="1.2"
        />

        <rect
          :for={lane <- @model.lanes}
          x="0"
          y={lane.y}
          width={@model.svg_width}
          height={lane.height}
          fill="var(--ui-timeline-lane)"
          fill-opacity={lane.opacity}
        />

        <rect
          :for={entry <- @model.entries}
          x={entry.x}
          y={entry.y}
          width={entry.width}
          height={entry.height}
          rx="3"
          fill={entry.fill}
          fill-opacity="1"
        />

        <text
          :for={entry <- @model.entries}
          x={entry.x + 6}
          y={entry.text_y}
          fill={Map.get(entry, :text_fill, "var(--ui-timeline-label)")}
          fill-opacity="0.9"
          font-size="10"
          font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, Liberation Mono, Courier New, monospace"
        >
          {entry.label}
        </text>

        <text
          :for={{x, bar_number} <- @model.bar_xs}
          x={x + 2}
          y="13"
          fill="var(--ui-timeline-bar-label)"
          fill-opacity="0.85"
          font-size="10"
          font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, Liberation Mono, Courier New, monospace"
        >
          B{bar_number}
        </text>

        <line
          :if={not is_nil(@model.playhead_x)}
          x1={@model.playhead_x}
          x2={@model.playhead_x}
          y1="0"
          y2={@model.svg_height}
          stroke="var(--ui-playhead)"
          stroke-opacity="0.9"
          stroke-width="1.5"
        />
      </svg>

      <div class="flex items-center justify-between font-mono text-[10px] text-zinc-500">
        <span>0</span>
        <span>{@model.total_mbeats} mbeats</span>
      </div>
    </div>
    """
  end

  defp start_playback(socket, render_data) do
    Player.play(render_data)
    playback_ref = make_ref()
    Process.send_after(self(), {:refresh_player, playback_ref}, @refresh_interval_ms)
    playing_duration_ms = Map.get(render_data, :duration_ms)
    done_after_ms = playing_duration_ms
    Process.send_after(self(), {:playback_done, playback_ref}, done_after_ms)
    play_started_at = System.monotonic_time(:millisecond)

    socket
    |> assign(:player_status, Player.status())
    |> assign(:play_started_at, play_started_at)
    |> assign(:playing_duration_ms, playing_duration_ms)
    |> assign(:playback_ref, playback_ref)
    |> assign(:playhead_pct, playhead_pct(:playing, play_started_at, playing_duration_ms))
  end

  defp start_active_playback(socket) do
    case active_playback_render_data(socket) do
      nil ->
        socket

      render_data ->
        start_playback(socket, render_data)
    end
  end

  defp active_playback_render_data(socket) do
    active_entries =
      compact_active_entries(
        socket.assigns.sample_entries,
        socket.assigns.sample_context,
        socket.assigns.active_chord_indices
      )

    case active_entries do
      [] -> nil
      entries -> PerformanceAssembler.generate_sample(entries, socket.assigns.sample_context)
    end
  end

  defp compact_active_entries(
         sample_entries,
         %SampleContext{} = sample_context,
         active_chord_indices
       )
       when is_list(sample_entries) and is_list(active_chord_indices) do
    active_set = MapSet.new(active_chord_indices)

    sample_entries
    |> Enum.with_index()
    |> Enum.filter(fn {_entry, index} -> MapSet.member?(active_set, index) end)
    |> Enum.sort_by(fn {_entry, index} -> index end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.reduce({0, []}, fn entry, {cursor_mbeat, acc} ->
      timeline_context = Map.fetch!(entry, :timeline_context)
      duration_mbeats = TimelineContext.duration_mbeats(timeline_context)

      compact_timeline_context = %TimelineContext{
        start_beat: SampleContext.mbeat_to_position(sample_context, cursor_mbeat),
        duration_mbeats: duration_mbeats
      }

      compact_entry = Map.put(entry, :timeline_context, compact_timeline_context)
      {cursor_mbeat + duration_mbeats, [compact_entry | acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp clear_playback_state(socket, manual_stop) when is_boolean(manual_stop) do
    socket
    |> assign(:play_started_at, nil)
    |> assign(:playing_duration_ms, nil)
    |> assign(:playhead_pct, nil)
    |> assign(:playback_ref, nil)
    |> assign(:manual_stop, manual_stop)
  end

  defp playhead_pct(:playing, play_started_at, duration_ms)
       when is_integer(duration_ms) and duration_ms > 0 and not is_nil(play_started_at) do
    (System.monotonic_time(:millisecond) - play_started_at)
    |> max(0)
    |> min(duration_ms)
    |> Kernel./(duration_ms)
    |> Kernel.*(100)
  end

  defp playhead_pct(:playing, play_started_at, duration_ms)
       when not is_nil(play_started_at) and duration_ms > 0 do
    (System.monotonic_time(:millisecond) - play_started_at)
    |> max(0)
    |> min(duration_ms)
    |> Kernel./(duration_ms)
    |> Kernel.*(100)
  end

  defp playhead_pct(_player_status, _play_started_at, _duration_ms), do: nil

  defp loop_full_sample?(socket) do
    socket.assigns.loop_full_sample and
      not socket.assigns.manual_stop and
      not is_nil(socket.assigns.render_data)
  end

  # Flattens every frame (one row per note) for a raw, at-a-glance table
  # of exactly what the note-on/pressure/bend/slide sequence looks like
  # across the whole chord performance.
  defp debug_rows(frames, sample_entries, active_chord_indices, on_filter, off_filter) do
    chord_labels_by_entry =
      sample_entries
      |> Enum.with_index()
      |> Map.new(fn {%{chord_spec: chord_spec}, index} ->
        {index, short_chord_label(chord_spec)}
      end)

    note_spelling = preferred_note_spelling(sample_entries)
    active_set = MapSet.new(active_chord_indices)

    Enum.flat_map(frames, fn frame ->
      frame.notes
      |> Enum.filter(fn note ->
        MapSet.member?(active_set, Map.get(note, :sample_entry_index, -1)) and
          bool_filter_match?(note.note_on, on_filter) and
          bool_filter_match?(note.note_off, off_filter)
      end)
      |> Enum.map(fn note ->
        note
        |> Map.put(:at_ms, frame.at_ms)
        |> Map.put(:chord_id, note.sample_entry_index)
        |> Map.put(:chord_label, Map.get(chord_labels_by_entry, note.sample_entry_index, "-"))
        |> Map.put(:note_label, format_note_label(note.note_name, note.octave, note_spelling))
      end)
    end)
  end

  defp selected_sample_entry(sample_entries, selected_index)
       when is_list(sample_entries) and is_integer(selected_index) do
    Enum.at(sample_entries, selected_index)
  end

  defp normalize_bool_filter("true"), do: true
  defp normalize_bool_filter("false"), do: false
  defp normalize_bool_filter("no_filter"), do: :no_filter
  defp normalize_bool_filter(_), do: :no_filter

  defp bool_filter_match?(_value, :no_filter), do: true
  defp bool_filter_match?(true, true), do: true
  defp bool_filter_match?(false, false), do: true
  defp bool_filter_match?(_value, _filter), do: false

  defp all_chord_indices(sample_entries) when is_list(sample_entries) do
    sample_entries
    |> Enum.with_index()
    |> Enum.map(fn {_entry, index} -> index end)
  end

  defp toggle_chord_index(active_indices, index) do
    active_set = MapSet.new(active_indices)

    next_set =
      if MapSet.member?(active_set, index) do
        if MapSet.size(active_set) == 1 do
          active_set
        else
          MapSet.delete(active_set, index)
        end
      else
        MapSet.put(active_set, index)
      end

    next_set
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp chord_active?(active_indices, index), do: index in active_indices

  defp selected_scope_mbeats(
         sample_entries,
         sample_context,
         active_chord_indices,
         fallback_end_mbeat
       ) do
    bounds_by_index =
      sample_entries
      |> Enum.with_index()
      |> Enum.map(fn {%{timeline_context: timeline_context}, index} ->
        start_mbeat = SampleContext.position_to_mbeat(sample_context, timeline_context.start_beat)
        end_mbeat = start_mbeat + TimelineContext.duration_mbeats(timeline_context)
        %{index: index, start_mbeat: start_mbeat, end_mbeat: end_mbeat}
      end)

    selected_bounds = Enum.filter(bounds_by_index, &(&1.index in active_chord_indices))

    case selected_bounds do
      [] ->
        {0, fallback_end_mbeat}

      _ ->
        {
          Enum.min_by(selected_bounds, & &1.start_mbeat).start_mbeat,
          Enum.max_by(selected_bounds, & &1.end_mbeat).end_mbeat
        }
    end
  end

  defp scope_frames(frames, window_start_mbeat, window_end_mbeat) do
    Enum.filter(frames, fn frame ->
      frame.at_mbeat >= window_start_mbeat and frame.at_mbeat <= window_end_mbeat
    end)
  end

  defp preferred_note_spelling(sample_entries) when is_list(sample_entries) do
    roots = Enum.map(sample_entries, fn entry -> entry.chord_spec.root end)

    has_flat_class_root? = Enum.any?(roots, &(&1 in [:a_sharp, :d_sharp, :g_sharp]))
    has_sharp_class_root? = Enum.any?(roots, &(&1 in [:c_sharp, :f_sharp]))

    if has_flat_class_root? and not has_sharp_class_root? do
      :flat
    else
      :sharp
    end
  end

  defp format_note_label(note_name, octave, spelling)
       when is_atom(note_name) and is_integer(octave) do
    map = if spelling == :flat, do: @flat_note_display, else: @sharp_note_display

    case Map.fetch(map, note_name) do
      {:ok, pitch} -> "#{pitch}#{octave}"
      :error -> "#{note_name}#{octave}"
    end
  end

  defp active_sample_name(samples, active_sample_index)
       when is_list(samples) and is_integer(active_sample_index) do
    samples
    |> Enum.at(active_sample_index, %{})
    |> Map.get(:name, "Unnamed")
  end

  defp sample_context_label(%SampleContext{} = sample_context) do
    {num, den} = sample_context.time_signature
    "#{sample_context.bpm} bpm · #{num}/#{den}"
  end

  defp table_chord_label(%ChordSpec{} = chord_spec) do
    root = chord_spec.root |> Atom.to_string() |> String.replace("_sharp", "#") |> String.upcase()
    modifier = table_modifier_label(chord_spec.modifier)
    "#{root} #{modifier} · o#{chord_spec.octave} i#{chord_spec.inversion}"
  end

  defp table_modifier_label(:major), do: "maj"
  defp table_modifier_label(:minor), do: "min"
  defp table_modifier_label(:dominant_seventh), do: "7"
  defp table_modifier_label(:major_seventh), do: "maj7"
  defp table_modifier_label(:minor_seventh), do: "m7"
  defp table_modifier_label(:minor_major_seventh), do: "mMaj7"
  defp table_modifier_label(:diminished), do: "dim"
  defp table_modifier_label(:half_diminished), do: "m7b5"
  defp table_modifier_label(:augmented), do: "aug"
  defp table_modifier_label(modifier), do: Atom.to_string(modifier)

  defp machine_label(machine) do
    machine
    |> Mensch.Machine.id()
    |> Atom.to_string()
  end

  defp machine_icon_name(%Mensch.Machines.SimpleChord{}), do: "hero-rectangle-group"
  defp machine_icon_name(%Mensch.Machines.ArpMachine{}), do: "hero-arrows-up-down"
  defp machine_icon_name(_machine), do: "hero-cpu-chip"

  defp build_sample_folders(samples) when is_list(samples) do
    indexed_samples = Enum.with_index(samples)

    grouped_by_folder =
      Enum.group_by(indexed_samples, fn {sample, _index} ->
        Map.get(sample, :folder, "Unfiled")
      end)

    preferred_order = ["Dynamic Voicing", "Arp Machine", "Simple Chord", "Legacy"]

    folder_names =
      preferred_order ++
        (grouped_by_folder
         |> Map.keys()
         |> Enum.reject(&(&1 in preferred_order))
         |> Enum.sort())

    folder_names
    |> Enum.map(fn folder_name ->
      %{name: folder_name, samples: Map.get(grouped_by_folder, folder_name, [])}
    end)
    |> Enum.reject(fn folder -> folder.samples == [] end)
  end

  defp table_start_label(%SampleContext{} = sample_context, %BeatPosition{} = start_beat) do
    mbeat = SampleContext.position_to_mbeat(sample_context, start_beat)
    ms = SampleContext.mbeats_to_ms(sample_context, mbeat)

    "b#{start_beat.bar}.#{start_beat.beat} · #{SampleContext.format_timestamp(ms)}"
  end

  defp table_duration_label(
         %SampleContext{} = sample_context,
         %TimelineContext{} = timeline_context
       ) do
    duration_mbeats = TimelineContext.duration_mbeats(timeline_context)
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    duration_ms = SampleContext.mbeats_to_ms(sample_context, duration_mbeats)
    duration_s = duration_ms / 1000
    duration_s_label = :erlang.float_to_binary(duration_s, decimals: 2)

    musical =
      cond do
        rem(duration_mbeats, mbeats_per_bar) == 0 ->
          "#{div(duration_mbeats, mbeats_per_bar)}b"

        rem(duration_mbeats, mbeats_per_beat) == 0 ->
          "#{div(duration_mbeats, mbeats_per_beat)}bt"

        true ->
          beats = div(duration_mbeats, mbeats_per_beat)
          remainder_mbeats = rem(duration_mbeats, mbeats_per_beat)
          "#{beats}bt+#{remainder_mbeats}m"
      end

    "#{musical} · #{duration_s_label}s"
  end

  defp sample_duration_label(sample_entries, %SampleContext{} = sample_context)
       when is_list(sample_entries) do
    duration_ms = sample_duration_ms(sample_entries, sample_context)
    minutes = div(duration_ms, 60_000)
    seconds = div(rem(duration_ms, 60_000), 1000)
    millis = rem(duration_ms, 1000)

    "#{minutes}m #{seconds}s #{millis}ms"
  end

  defp sample_duration_ms(sample_entries, %SampleContext{} = sample_context)
       when is_list(sample_entries) do
    max_end_mbeat =
      case sample_entries do
        [] ->
          0

        _ ->
          sample_entries
          |> Enum.map(fn %{timeline_context: timeline_context} ->
            start_mbeat =
              SampleContext.position_to_mbeat(sample_context, timeline_context.start_beat)

            start_mbeat + TimelineContext.duration_mbeats(timeline_context)
          end)
          |> Enum.max()
      end

    SampleContext.mbeats_to_ms(sample_context, max_end_mbeat)
  end

  defp local_timeline_start_label do
    "bar 0 · beat 0 · 0ms"
  end

  defp local_timeline_end_label(%SampleContext{} = sample_context, duration_ms) do
    total_mbeats = SampleContext.ms_to_mbeats(sample_context, duration_ms)
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)

    bar = div(total_mbeats, mbeats_per_bar)
    bar_remainder = rem(total_mbeats, mbeats_per_bar)
    beat = div(bar_remainder, mbeats_per_beat)
    mbeat_remainder = rem(bar_remainder, mbeats_per_beat)

    musical_label =
      if mbeat_remainder == 0 do
        "bar #{bar} · beat #{beat}"
      else
        "bar #{bar} · beat #{beat} + #{mbeat_remainder}mbeats"
      end

    "#{musical_label} · #{duration_ms}ms"
  end

  defp sample_timeline_static_model(sample_entries, %SampleContext{} = sample_context) do
    svg_width = 1000
    lane_height = 22
    lane_gap = 8
    lanes_top = 22
    lanes_bottom = 12

    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    mbeats_per_subbeat = max(div(mbeats_per_beat, 4), 1)

    entries =
      sample_entries
      |> Enum.with_index()
      |> Enum.map(fn {%{chord_spec: chord_spec, timeline_context: timeline_context}, index} ->
        start_mbeat = SampleContext.position_to_mbeat(sample_context, timeline_context.start_beat)
        end_mbeat = start_mbeat + TimelineContext.duration_mbeats(timeline_context)

        %{
          index: index,
          label: short_chord_label(chord_spec),
          start_mbeat: start_mbeat,
          end_mbeat: end_mbeat
        }
      end)

    max_end_mbeat =
      case entries do
        [] -> mbeats_per_bar * 2
        _ -> entries |> Enum.map(& &1.end_mbeat) |> Enum.max()
      end

    total_mbeats = max(max_end_mbeat, 1)
    bar_count = total_mbeats / mbeats_per_bar
    beat_count = total_mbeats / mbeats_per_beat
    total_mbeats = max(total_mbeats, 1)
    row_count = max(length(entries), 1)
    lanes_height = row_count * lane_height + (row_count - 1) * lane_gap
    svg_height = lanes_top + lanes_height + lanes_bottom

    lanes =
      for lane_index <- 0..(row_count - 1) do
        %{
          y: lanes_top + lane_index * (lane_height + lane_gap),
          height: lane_height,
          opacity: if(rem(lane_index, 2) == 0, do: "0.02", else: "0.05")
        }
      end

    entries_with_geometry =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {%{
                        index: source_index,
                        label: label,
                        start_mbeat: start_mbeat,
                        end_mbeat: end_mbeat
                      }, lane_index} ->
        lane_y = lanes_top + lane_index * (lane_height + lane_gap)
        x = mbeat_to_svg_x(start_mbeat, total_mbeats)
        width = max(mbeat_to_svg_x(end_mbeat, total_mbeats) - x, 8)

        %{
          index: source_index,
          label: label,
          x: x,
          y: lane_y + 1,
          width: width,
          height: lane_height - 2,
          text_y: lane_y + 14,
          fill: timeline_color(source_index)
        }
      end)

    %{
      svg_width: svg_width,
      svg_height: svg_height,
      lanes: lanes,
      entries: entries_with_geometry,
      source_entries: entries,
      subbeat_xs: timeline_xs(total_mbeats, mbeats_per_subbeat),
      beat_xs: timeline_xs(total_mbeats, mbeats_per_beat),
      bar_xs:
        timeline_xs(total_mbeats, mbeats_per_bar)
        |> Enum.with_index(1),
      row_count: row_count,
      bar_count: bar_count,
      beat_count: beat_count,
      total_mbeats: total_mbeats
    }
  end

  defp sample_timeline_with_playhead(nil, _render_scope, _playhead_pct, _active_chord_indices),
    do: nil

  defp sample_timeline_with_playhead(
         %{
           source_entries: source_entries,
           total_mbeats: total_mbeats
         } = model,
         render_scope,
         playhead_pct,
         active_chord_indices
       ) do
    playhead_x =
      timeline_playhead_x(
        playhead_pct,
        render_scope,
        source_entries,
        total_mbeats,
        active_chord_indices
      )

    active_set = MapSet.new(active_chord_indices)
    source_entries_by_index = Map.new(source_entries, &{&1.index, &1})

    {window_start, window_end} =
      case Enum.filter(source_entries, &MapSet.member?(active_set, &1.index)) do
        [] ->
          {0, total_mbeats}

        selected ->
          {
            Enum.min_by(selected, & &1.start_mbeat).start_mbeat,
            Enum.max_by(selected, & &1.end_mbeat).end_mbeat
          }
      end

    styled_entries =
      Enum.map(model.entries, fn entry ->
        source_entry = Map.get(source_entries_by_index, entry.index)

        in_window =
          (source_entry &&
             source_entry.start_mbeat < window_end) and source_entry.end_mbeat > window_start

        is_active = MapSet.member?(active_set, entry.index)
        state = timeline_entry_state(is_active, in_window)

        entry
        |> Map.put(:fill, timeline_entry_fill(state, entry.index))
        |> Map.put(:text_fill, timeline_entry_text_fill(state))
      end)

    model
    |> Map.put(:entries, styled_entries)
    |> Map.put(:playhead_x, playhead_x)
  end

  defp timeline_entry_state(true, _in_window), do: :active
  defp timeline_entry_state(false, true), do: :inactive_in_window
  defp timeline_entry_state(false, false), do: :inactive_outside_window

  defp timeline_entry_fill(:active, index), do: timeline_color(index)
  defp timeline_entry_fill(:inactive_in_window, _index), do: "#303844"
  defp timeline_entry_fill(:inactive_outside_window, _index), do: "#252c36"

  defp timeline_entry_text_fill(:active), do: "var(--ui-timeline-label)"
  defp timeline_entry_text_fill(:inactive_in_window), do: "#7D8898"
  defp timeline_entry_text_fill(:inactive_outside_window), do: "#626D7D"

  defp timeline_playhead_x(nil, _render_scope, _entries, _total_mbeats, _active_chord_indices),
    do: nil

  defp timeline_playhead_x(
         playhead_pct,
         :full_sample,
         entries,
         total_mbeats,
         active_chord_indices
       )
       when is_number(playhead_pct) do
    clamped_pct = max(min(playhead_pct, 100), 0)

    active_entries =
      entries
      |> Enum.filter(&(&1.index in active_chord_indices))
      |> Enum.sort_by(& &1.start_mbeat)

    case active_entries do
      [] ->
        mbeat_to_svg_x(total_mbeats * (clamped_pct / 100), total_mbeats)

      _ ->
        total_active_mbeats =
          active_entries
          |> Enum.map(&max(&1.end_mbeat - &1.start_mbeat, 0))
          |> Enum.sum()
          |> max(1)

        compact_playhead_mbeat = total_active_mbeats * (clamped_pct / 100)

        absolute_playhead_mbeat =
          active_entries
          |> Enum.reduce_while({compact_playhead_mbeat, 0}, fn entry, {remaining, _acc} ->
            entry_duration = max(entry.end_mbeat - entry.start_mbeat, 0)

            cond do
              remaining <= entry_duration ->
                {:halt, {remaining, entry.start_mbeat + remaining}}

              true ->
                {:cont, {remaining - entry_duration, entry.end_mbeat}}
            end
          end)
          |> elem(1)

        mbeat_to_svg_x(absolute_playhead_mbeat, total_mbeats)
    end
  end

  defp timeline_playhead_x(
         playhead_pct,
         {:entry, index},
         entries,
         total_mbeats,
         _active_chord_indices
       )
       when is_number(playhead_pct) and is_integer(index) do
    case Enum.at(entries, index) do
      %{start_mbeat: start_mbeat, end_mbeat: end_mbeat} ->
        start_x = mbeat_to_svg_x(start_mbeat, total_mbeats)
        end_x = mbeat_to_svg_x(end_mbeat, total_mbeats)
        Float.round(start_x + (end_x - start_x) * (playhead_pct / 100), 2)

      _ ->
        nil
    end
  end

  defp timeline_playhead_x(
         _playhead_pct,
         _render_scope,
         _entries,
         _total_mbeats,
         _active_chord_indices
       ),
       do: nil

  defp timeline_color(index) do
    Enum.at(@chart_colors, rem(index, length(@chart_colors)))
  end

  defp entry_color_dot_style(index) do
    color = timeline_color(index)

    "background-color: #{color};"
  end

  defp short_chord_label(%ChordSpec{} = chord_spec) do
    root = chord_spec.root |> Atom.to_string() |> String.replace("_sharp", "#") |> String.upcase()
    modifier = chord_spec.modifier |> Atom.to_string()
    "#{root} #{modifier}"
  end

  defp timeline_xs(total_mbeats, step) do
    0..total_mbeats//step
    |> Enum.map(&mbeat_to_svg_x(&1, total_mbeats))
  end

  defp mbeat_to_svg_x(mbeat, total_mbeats) do
    mbeat
    |> Kernel./(total_mbeats)
    |> Kernel.*(1000)
    |> Float.round(2)
  end

  defp chart_grid_model(%SampleContext{} = sample_context, total_mbeats) do
    width = 600
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    mbeats_per_subbeat = max(div(mbeats_per_beat, 4), 1)
    total_mbeats = max(total_mbeats, 1)

    %{
      subbeat_xs: chart_grid_xs(total_mbeats, mbeats_per_subbeat, width),
      beat_xs: chart_grid_xs(total_mbeats, mbeats_per_beat, width),
      bar_xs: chart_grid_xs(total_mbeats, mbeats_per_bar, width)
    }
  end

  defp note_matrix_grid_model(%SampleContext{} = sample_context, total_mbeats) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    mbeats_per_subbeat = max(div(mbeats_per_beat, 4), 1)
    total_mbeats = max(total_mbeats, 1)

    %{
      subbeat_pcts: timeline_pct_marks(total_mbeats, mbeats_per_subbeat),
      beat_pcts: timeline_pct_marks(total_mbeats, mbeats_per_beat),
      bar_pcts: timeline_pct_marks(total_mbeats, mbeats_per_bar)
    }
  end

  defp timeline_pct_marks(total_mbeats, step) do
    0..total_mbeats//step
    |> Enum.map(fn mbeat -> Float.round(mbeat / total_mbeats * 100, 3) end)
  end

  defp chart_grid_xs(total_mbeats, step, width) do
    0..total_mbeats//step
    |> Enum.map(fn mbeat -> Float.round(mbeat / total_mbeats * width, 2) end)
  end

  # Groups a rendered timeline's frames by note (`{channel,
  # midi_note}`), one polyline per note, for an SVG line chart of `value_key`
  # (`:pressure`, `:bend`, or `:slide`) over time.
  defp build_chart(
         frames,
         value_key,
         {min_v, max_v},
         render_scope,
         selected_note_key,
         active_chord_indices,
         window_start_mbeat,
         %SampleContext{} = _sample_context,
         total_mbeats
       ) do
    colors = note_color_map(frames, render_scope, selected_note_key, active_chord_indices)
    total_mbeats = max(total_mbeats, 1)

    frames
    |> Enum.flat_map(fn frame ->
      local_mbeat = max(frame.at_mbeat - window_start_mbeat, 0)
      x = local_mbeat / total_mbeats * 600

      Enum.map(frame.notes, fn note ->
        {note_series_key(note), x, Map.fetch!(note, value_key)}
      end)
    end)
    |> Enum.group_by(
      fn {id, _x, _value} -> id end,
      fn {_id, x, value} -> {x, value} end
    )
    |> Enum.map(fn {series_key, points} ->
      {channel, midi_note} = series_channel_note(series_key)

      %{
        series_key: series_key,
        channel: channel,
        midi_note: midi_note,
        color: Map.fetch!(colors, series_key),
        points: chart_points(points, min_v, max_v)
      }
    end)
    |> Enum.sort_by(&chart_series_sort_key(&1, selected_note_key))
  end

  defp chart_series_sort_key(series, selected_note_key) do
    is_selected =
      not is_nil(selected_note_key) and {series.channel, series.midi_note} == selected_note_key

    {is_selected, series.channel, series.midi_note}
  end

  # A piano-roll style matrix: one row per semitone between the lowest
  # and highest sounding note (highest pitch on top), so vertical
  # spacing matches real chromatic distance. A row may contain multiple
  # bars (same pitch reused later by another chord/channel).
  defp build_note_matrix(
         frames,
         render_scope,
         selected_note_key,
         active_chord_indices,
         window_start_mbeat,
         %SampleContext{} = _sample_context,
         total_mbeats
       ) do
    colors = note_color_map(frames, render_scope, selected_note_key, active_chord_indices)
    total_mbeats = max(total_mbeats, 1)

    segments =
      frames
      |> Enum.flat_map(fn frame ->
        Enum.map(frame.notes, &{&1, frame.at_mbeat - window_start_mbeat})
      end)
      |> Enum.group_by(fn {note, _at_mbeat} -> note_series_key(note) end)
      |> Enum.flat_map(fn {series_key, entries} ->
        {channel, midi_note_number} = series_channel_note(series_key)

        entries
        |> lifecycle_segments(total_mbeats)
        |> Enum.map(fn %{start_mbeat: start_mbeat, end_mbeat: end_mbeat, label: label} ->
          left_pct = start_mbeat / total_mbeats * 100
          width_pct = max((end_mbeat - start_mbeat) / total_mbeats * 100, 0.5)

          style =
            "left: #{Float.round(left_pct * 1.0, 2)}%; " <>
              "width: #{Float.round(width_pct * 1.0, 2)}%; " <>
              "background-color: #{Map.fetch!(colors, series_key)};"

          %{
            series_key: series_key,
            channel: channel,
            midi_note: midi_note_number,
            label: label,
            active: note_selected?({channel, midi_note_number}, selected_note_key),
            style: style
          }
        end)
      end)

    case segments do
      [] ->
        []

      _ ->
        rows_by_note =
          segments
          |> Enum.group_by(& &1.midi_note)

        {min_note, max_note} = rows_by_note |> Map.keys() |> Enum.min_max()

        for note_number <- max_note..min_note//-1 do
          case Map.get(rows_by_note, note_number) do
            nil ->
              {note_name, octave} = PerformanceAssembler.note_name(note_number)

              %{
                midi_note: note_number,
                label: "#{note_name}#{octave}",
                segments: [],
                has_active_segment: false
              }

            note_segments ->
              label = note_segments |> hd() |> Map.fetch!(:label)

              segments =
                note_segments
                |> Enum.map(fn segment ->
                  %{
                    style: segment.style,
                    channel: segment.channel,
                    midi_note: segment.midi_note,
                    active: segment.active
                  }
                end)

              %{
                midi_note: note_number,
                label: label,
                segments: segments,
                has_active_segment: Enum.any?(segments, & &1.active)
              }
          end
        end
    end
  end

  defp lifecycle_segments(entries, total_mbeats) do
    {segments, open_segment} =
      entries
      |> Enum.sort_by(fn {_note, at_mbeat} -> at_mbeat end)
      |> Enum.reduce({[], nil}, fn {note, at_mbeat}, {acc, open} ->
        label = "#{note.note_name}#{note.octave}"

        cond do
          note.note_on and is_nil(open) ->
            {acc, %{start_mbeat: at_mbeat, label: label}}

          note.note_on and not is_nil(open) ->
            closed = Map.put(open, :end_mbeat, at_mbeat)
            {[closed | acc], %{start_mbeat: at_mbeat, label: label}}

          note.note_off and not is_nil(open) ->
            closed = Map.put(open, :end_mbeat, at_mbeat)
            {[closed | acc], nil}

          true ->
            {acc, open}
        end
      end)

    segments =
      if is_nil(open_segment) do
        segments
      else
        [Map.put(open_segment, :end_mbeat, total_mbeats) | segments]
      end

    segments
    |> Enum.reverse()
    |> Enum.filter(fn segment -> segment.end_mbeat >= segment.start_mbeat end)
  end

  # Assigns each distinct logical note-event key a stable color shared by both
  # the line charts and the note matrix, preventing channel/note reuse from
  # inheriting colors across distinct events.
  defp note_color_map(frames, render_scope, selected_note_key, active_chord_indices) do
    frames
    |> base_note_color_map(render_scope)
    |> Map.new(fn {note_key, color} ->
      {note_key, focus_color(note_key, color, selected_note_key, active_chord_indices)}
    end)
  end

  defp base_note_color_map(frames, {:entry, entry_index}) when is_integer(entry_index) do
    base_color = timeline_color(entry_index)
    events = frames |> distinct_note_events() |> sort_voice_events()
    total = length(events)

    events
    |> Enum.with_index()
    |> Map.new(fn {event, index} ->
      {note_series_key(event), color_with_alpha(base_color, voice_alpha(index, total))}
    end)
  end

  defp base_note_color_map(frames, :full_sample) do
    frames
    |> distinct_note_events()
    |> Enum.group_by(&Map.get(&1, :sample_entry_index, 0))
    |> Enum.flat_map(fn {entry_index, events} ->
      base_color = timeline_color(entry_index)

      events
      |> sort_voice_events()
      |> then(fn sorted_events -> {sorted_events, length(sorted_events)} end)
      |> then(fn {sorted_events, total} ->
        sorted_events
        |> Enum.with_index()
        |> Enum.map(fn {event, index} ->
          {note_series_key(event), color_with_alpha(base_color, voice_alpha(index, total))}
        end)
      end)
    end)
    |> Map.new()
  end

  defp base_note_color_map(frames, _render_scope) do
    frames
    |> Enum.flat_map(& &1.notes)
    |> Enum.uniq_by(&note_series_key/1)
    |> Enum.sort_by(fn event ->
      {Map.get(event, :sample_entry_index, -1), Map.get(event, :note_instance_id, 999),
       event.midi_note, event.channel}
    end)
    |> Enum.with_index()
    |> Map.new(fn {event, index} ->
      {note_series_key(event), Enum.at(@chart_colors, rem(index, length(@chart_colors)))}
    end)
  end

  defp note_selected?(_note_key, nil), do: true
  defp note_selected?(note_key, selected_note_key), do: note_key == selected_note_key

  defp focus_color(series_key, color, nil, active_chord_indices) do
    if note_in_active_chords?(series_key, active_chord_indices),
      do: color,
      else: @inactive_note_color
  end

  defp focus_color(series_key, color, {selected_channel, selected_note}, active_chord_indices) do
    {channel, midi_note} = series_channel_note(series_key)

    if channel == selected_channel and midi_note == selected_note and
         note_in_active_chords?(series_key, active_chord_indices) do
      color
    else
      @inactive_note_color
    end
  end

  defp focus_color(series_key, color, _selected_note_key, active_chord_indices) do
    if note_in_active_chords?(series_key, active_chord_indices),
      do: color,
      else: @inactive_note_color
  end

  defp note_in_active_chords?(series_key, active_chord_indices) do
    {entry_index, _machine_id, _chord_instance_id, _note_instance_id, _note, _channel} =
      series_key

    entry_index in active_chord_indices
  end

  defp selected_note_label(nil), do: "all"

  defp selected_note_label({channel, note_number}) do
    {note_name, octave} = PerformanceAssembler.note_name(note_number)

    pretty_note_name =
      note_name
      |> Atom.to_string()
      |> String.replace("_sharp", "#")
      |> String.upcase()

    "#{pretty_note_name}#{octave} · ch #{channel}"
  end

  defp distinct_note_events(frames) do
    frames
    |> Enum.flat_map(& &1.notes)
    |> Enum.uniq_by(&note_series_key/1)
  end

  defp sort_voice_events(events) do
    Enum.sort_by(events, fn event ->
      {Map.get(event, :sample_entry_index, -1), Map.get(event, :machine_id, :unknown),
       Map.get(event, :chord_instance_id, 0), Map.get(event, :note_instance_id, 999),
       event.midi_note, event.channel}
    end)
  end

  defp note_series_key(note) do
    {
      Map.get(note, :sample_entry_index, -1),
      Map.get(note, :machine_id, :unknown),
      Map.get(note, :chord_instance_id, 0),
      Map.get(note, :note_instance_id, 0),
      Map.get(note, :midi_note, 0),
      Map.get(note, :channel, -1)
    }
  end

  defp series_channel_note(
         {_entry_index, _machine_id, _chord_instance_id, _note_instance_id, note, channel}
       ) do
    {channel, note}
  end

  defp voice_alpha(_index, total) when total <= 1, do: 0.92

  defp voice_alpha(index, total) do
    # Keep a fixed contrast range regardless of chord size.
    max_alpha = 0.92
    min_alpha = 0.32
    t = index / max(total - 1, 1)
    Float.round(max_alpha - (max_alpha - min_alpha) * t, 2)
  end

  defp color_with_alpha("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>, alpha) do
    {r_i, _} = Integer.parse(r, 16)
    {g_i, _} = Integer.parse(g, 16)
    {b_i, _} = Integer.parse(b, 16)
    "rgba(#{r_i}, #{g_i}, #{b_i}, #{alpha})"
  end

  defp color_with_alpha(color, _alpha), do: color

  defp chart_points(points, min_v, max_v) do
    range = max(max_v - min_v, 0.0001)

    points
    |> Enum.sort_by(fn {x, _value} -> x end)
    |> Enum.map_join(" ", fn {x, value} ->
      y = 120 - (value - min_v) / range * 120
      "#{Float.round(x * 1.0, 1)},#{Float.round(y * 1.0, 1)}"
    end)
  end

  defp detail_total_mbeats(frames, duration_ms, %SampleContext{} = sample_context) do
    mbeat_by_duration = SampleContext.ms_to_mbeats(sample_context, duration_ms)
    mbeat_by_frames = frames |> List.last() |> then(&if(&1, do: &1.at_mbeat, else: 0))

    max(max(mbeat_by_duration, mbeat_by_frames), 1)
  end

  defp assign_detail_content(socket) do
    case socket.assigns.render_data do
      nil ->
        socket
        |> assign(:pressure_chart, [])
        |> assign(:slide_chart, [])
        |> assign(:bend_chart, [])
        |> assign(:debug_rows, [])
        |> assign(:note_matrix, [])
        |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
        |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})

      %{frames: frames, duration_ms: duration_ms} ->
        full_total_mbeats =
          detail_total_mbeats(frames, duration_ms, socket.assigns.sample_context)

        {window_start_mbeat, window_end_mbeat} =
          selected_scope_mbeats(
            socket.assigns.sample_entries,
            socket.assigns.sample_context,
            socket.assigns.active_chord_indices,
            full_total_mbeats
          )

        scoped_frames = scope_frames(frames, window_start_mbeat, window_end_mbeat)
        scoped_total_mbeats = max(window_end_mbeat - window_start_mbeat, 1)

        socket
        |> assign(
          :pressure_chart,
          build_chart(
            scoped_frames,
            :pressure,
            {0, 127},
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.active_chord_indices,
            window_start_mbeat,
            socket.assigns.sample_context,
            scoped_total_mbeats
          )
        )
        |> assign(
          :slide_chart,
          build_chart(
            scoped_frames,
            :slide,
            {0, 127},
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.active_chord_indices,
            window_start_mbeat,
            socket.assigns.sample_context,
            scoped_total_mbeats
          )
        )
        |> assign(
          :bend_chart,
          build_chart(
            scoped_frames,
            :bend,
            value_range(scoped_frames),
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.active_chord_indices,
            window_start_mbeat,
            socket.assigns.sample_context,
            scoped_total_mbeats
          )
        )
        |> assign(
          :debug_rows,
          debug_rows(
            scoped_frames,
            socket.assigns.sample_entries,
            socket.assigns.active_chord_indices,
            socket.assigns.debug_on_filter,
            socket.assigns.debug_off_filter
          )
        )
        |> assign(
          :note_matrix,
          build_note_matrix(
            scoped_frames,
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.active_chord_indices,
            window_start_mbeat,
            socket.assigns.sample_context,
            scoped_total_mbeats
          )
        )
        |> assign(
          :chart_grid,
          chart_grid_model(socket.assigns.sample_context, scoped_total_mbeats)
        )
        |> assign(
          :note_matrix_grid,
          note_matrix_grid_model(socket.assigns.sample_context, scoped_total_mbeats)
        )
    end
  end

  # Bend's absolute range is tiny (see `Mensch.NoteShape`'s
  # `@vibrato_depth`), so it gets its own dynamic min/max instead of
  # being squashed flat against a fixed +/-1.0 scale.
  defp value_range(frames) do
    values = for frame <- frames, note <- frame.notes, do: note.bend

    case Enum.min_max(values) do
      {same, same} -> {same - 0.0001, same + 0.0001}
      {min_v, max_v} -> {min_v, max_v}
    end
  end
end
