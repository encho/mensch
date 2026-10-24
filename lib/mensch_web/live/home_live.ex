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
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
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

    active_sample_index = 0

    active_sample = Enum.at(samples, active_sample_index, %{})
    sample_entries = Map.get(active_sample, :sample_entries, [])
    sample_total_length_mbeats = SampleDb.sample_total_length_mbeats(active_sample)

    sample_context =
      Map.get(active_sample, :sample_context, SampleDb.default_sample_context())

    {render_data, sample_warning} =
      render_data_and_warning(sample_entries, sample_context, sample_total_length_mbeats)

    midi_status = Mensch.Midi.Connection.status()

    socket =
      socket
      |> assign(:midi_status, midi_status)
      |> assign(:render_data, render_data)
      |> assign(:player_status, Player.status())
      |> assign(:play_started_at, nil)
      |> assign(:playing_duration_ms, nil)
      |> assign(:timeline_current_bar, nil)
      |> assign(:playback_ref, nil)
      |> assign(:pressure_chart, [])
      |> assign(:slide_chart, [])
      |> assign(:bend_chart, [])
      |> assign(:pressure_axis, pressure_slide_axis())
      |> assign(:slide_axis, pressure_slide_axis())
      |> assign(:bend_axis, bend_axis({-1.0, 1.0}))
      |> assign(:debug_rows, [])
      |> assign(:note_matrix, [])
      |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
      |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})
      |> assign(:samples, samples)
      |> assign(:active_sample_index, active_sample_index)
      |> assign(:sample_title_form, sample_title_form(Map.get(active_sample, :name, "")))
      |> assign(:sample_entries, sample_entries)
      |> assign(:active_chord_indices, all_chord_indices(sample_entries))
      |> assign(:sample_context, sample_context)
      |> assign(:sample_total_length_mbeats, sample_total_length_mbeats)
      |> assign(:sample_warning, sample_warning)
      |> assign(
        :sample_timeline_static,
        sample_timeline_static_model(sample_entries, sample_context, sample_total_length_mbeats)
      )
      |> assign(:render_scope, :full_sample)
      |> assign(:loop_full_sample, false)
      |> assign(:show_detail_panel, true)
      |> assign(:selected_sample_entry_index, nil)
      |> assign(:selected_note_key, nil)
      |> assign(:debug_on_filter, :no_filter)
      |> assign(:debug_off_filter, :no_filter)
      |> assign(:manual_stop, false)
      |> assign_detail_content()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sample_id = Map.get(params, "sample_id")

    case sample_index_from_param(socket.assigns.samples, sample_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Sample not found")
         |> push_navigate(to: ~p"/samples")}

      index when index == socket.assigns.active_sample_index ->
        {:noreply, socket}

      index ->
        {:noreply, assign_active_sample(socket, index)}
    end
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

  def handle_event("save_sample_title", %{"sample_title" => %{"name" => raw_title}}, socket) do
    current_sample = Enum.at(socket.assigns.samples, socket.assigns.active_sample_index, %{})
    sample_id = Map.get(current_sample, :id)

    with {:ok, normalized_sample_id} <- normalize_required_string(sample_id, "sample id"),
         {:ok, normalized_title} <- normalize_sample_title(raw_title),
         :ok <- SampleDb.rename_sample_title(normalized_sample_id, normalized_title) do
      updated_samples = update_sample_name_in_memory(socket.assigns.samples, normalized_sample_id, normalized_title)

      socket =
        socket
        |> assign(:samples, updated_samples)
        |> assign(:sample_title_form, sample_title_form(normalized_title))
        |> assign_active_sample(socket.assigns.active_sample_index)
        |> put_flash(:info, "Sample title saved")

      {:noreply, socket}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:sample_title_form, sample_title_form(raw_title || ""))
         |> put_flash(:error, "Could not save sample title: #{reason}")}
    end
  end

  @impl true
  def handle_info({:refresh_player, refresh_ref}, socket) do
    if socket.assigns.playback_ref != refresh_ref do
      {:noreply, socket}
    else
      status = Player.status()

      cond do
        status == :playing ->
          timeline_current_bar =
            timeline_current_bar_for_playback(
              socket,
              playhead_pct(
                status,
                socket.assigns.play_started_at,
                socket.assigns.playing_duration_ms
              )
            )

          socket =
            socket
            |> assign(:player_status, status)
            |> assign(:timeline_current_bar, timeline_current_bar)

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
        sample_timeline_with_current_bar(
          assigns.sample_timeline_static,
          assigns.render_scope,
          assigns.timeline_current_bar,
          assigns.active_chord_indices
        )
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:samples}>
      <div class="w-full">
        <div id="render-section" class="min-w-0 space-y-4">
          <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div class="space-y-1">
              <.form for={@sample_title_form} id="sample-title-form" phx-submit="save_sample_title">
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    id={@sample_title_form[:name].id}
                    name={@sample_title_form[:name].name}
                    value={@sample_title_form[:name].value}
                    maxlength="120"
                    class="h-10 w-[24rem] border-0 border-b border-transparent bg-transparent px-0 font-mono text-xl text-zinc-100 outline-none transition-colors duration-150 placeholder:text-zinc-500 hover:border-zinc-600 focus:border-cyan-300 md:w-[40rem] md:text-2xl"
                  />
                  <button
                    type="submit"
                    class="ui-radius-btn h-8 border border-emerald-300/70 bg-emerald-400/15 px-2.5 font-mono text-[10px] font-semibold uppercase tracking-wide text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/28"
                  >
                    Save Title
                  </button>
                </div>
              </.form>

              <div class="font-mono text-[11px] text-zinc-300">
                {sample_context_label(@sample_context)} · {sample_duration_label(
                  @sample_entries,
                  @sample_context,
                  @sample_total_length_mbeats
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

          <div
            :if={is_binary(@sample_warning)}
            class="ui-radius-btn flex w-full items-start gap-2 border border-amber-300/60 bg-amber-500/12 px-3 py-2 font-mono text-[11px] text-amber-100"
          >
            <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0 text-amber-200" />
            <span>{@sample_warning}</span>
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
                  class="group text-zinc-200 transition-colors duration-150 hover:bg-white/8"
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
                          "border-zinc-200 bg-zinc-100/15 text-zinc-100",
                        !chord_active?(@active_chord_indices, index) &&
                          "border-zinc-600 text-zinc-400 hover:border-zinc-300 hover:text-zinc-200"
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
            pressure_axis={@pressure_axis}
            slide_axis={@slide_axis}
            bend_axis={@bend_axis}
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
      </div>
    </Layouts.app>
    """
  end

  attr :model, :map, required: true

  defp sample_timeline(assigns) do
    ~H"""
    <div id="sample-timeline" class="space-y-2 bg-zinc-950/70 py-3">
      <div class="ui-chart-title flex items-center justify-between font-mono text-[11px] text-zinc-400">
        <span class="uppercase tracking-wide">Timeline</span>
        <span>
          {@model.row_count} rows · {@model.bar_count} bars · {@model.beat_count} beats · {@model.total_mbeats} mbeats
        </span>
      </div>

      <svg
        viewBox={"0 0 #{@model.svg_width} #{@model.svg_height}"}
        class="w-full overflow-visible bg-zinc-950/80"
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

        <circle
          :for={{x, bar_number} <- @model.bar_xs}
          cx={x}
          cy="10"
          r="6.5"
          fill={if active_bar_marker?(bar_number, @model.current_bar), do: "#FFFFFF", else: "#000000"}
          fill-opacity="0.95"
          stroke="var(--ui-grid-bar)"
          stroke-opacity="0.9"
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
          fill={Map.get(entry, :text_fill, "#000000")}
          fill-opacity="0.9"
          font-size="11"
          font-weight="400"
          font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, Liberation Mono, Courier New, monospace"
        >
          {entry.label}
        </text>

        <text
          :for={{x, bar_number} <- @model.bar_xs}
          x={x}
          y="10"
          fill={if active_bar_marker?(bar_number, @model.current_bar), do: "#000000", else: "#d1d5db"}
          fill-opacity="0.95"
          text-anchor="middle"
          dominant-baseline="middle"
          font-size="8"
          font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, Liberation Mono, Courier New, monospace"
        >
          B{bar_number}
        </text>

        <rect
          :for={region <- @model.current_bar_regions}
          x={region.x}
          y="0"
          width={region.width}
          height={@model.svg_height}
          fill="var(--ui-playhead)"
          fill-opacity="0.1"
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
    |> assign(
      :timeline_current_bar,
      timeline_current_bar_for_playback(
        socket,
        playhead_pct(:playing, play_started_at, playing_duration_ms)
      )
    )
  end

  defp start_active_playback(socket) do
    case active_playback_render_data(socket) do
      {:empty, _message, _entries} ->
        socket

      {:ok, render_data, entries} ->
        socket
        |> assign(
          :sample_warning,
          cycle_frame_balance_warning(entries, socket.assigns.sample_context)
        )
        |> start_playback(render_data)

      {:error, message, _entries} ->
        socket
        |> assign(:sample_warning, message)
        |> assign(:player_status, Player.status())
        |> clear_playback_state(true)
    end
  end

  defp active_playback_render_data(socket) do
    active_entries =
      playback_entries(
        socket.assigns.sample_entries,
        socket.assigns.sample_context,
        socket.assigns.active_chord_indices,
        socket.assigns.render_scope
      )

    case active_entries do
      [] ->
        {:empty, nil, active_entries}

      entries ->
        case generate_sample_safe(
               entries,
               socket.assigns.sample_context,
               socket.assigns.sample_total_length_mbeats
             ) do
          {:ok, render_data} -> {:ok, render_data, entries}
          {:error, message} -> {:error, message, entries}
        end
    end
  end

  defp playback_entries(sample_entries, _sample_context, active_chord_indices, :full_sample)
       when is_list(sample_entries) and is_list(active_chord_indices) do
    active_set = MapSet.new(active_chord_indices)

    sample_entries
    |> Enum.with_index()
    |> Enum.filter(fn {_entry, index} -> MapSet.member?(active_set, index) end)
    |> Enum.sort_by(fn {_entry, index} -> index end)
    |> Enum.map(&elem(&1, 0))
  end

  defp playback_entries(
         sample_entries,
         %SampleContext{} = sample_context,
         active_chord_indices,
         _render_scope
       )
       when is_list(sample_entries) and is_list(active_chord_indices) do
    compact_active_entries(sample_entries, sample_context, active_chord_indices)
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
    |> assign(:timeline_current_bar, nil)
    |> assign(:playback_ref, nil)
    |> assign(:manual_stop, manual_stop)
  end

  defp sample_index_from_param(samples, sample_id)
       when is_list(samples) and is_binary(sample_id) do
    Enum.find_index(samples, fn sample -> Map.get(sample, :id) == sample_id end)
  end

  defp sample_index_from_param(_samples, _sample_id), do: nil

  defp assign_active_sample(socket, index) when is_integer(index) do
    case Enum.at(socket.assigns.samples, index) do
      %{sample_entries: sample_entries, sample_context: sample_context} = sample ->
        Player.stop()

        sample_total_length_mbeats = SampleDb.sample_total_length_mbeats(sample)

        {render_data, sample_warning} =
          render_data_and_warning(sample_entries, sample_context, sample_total_length_mbeats)

        socket
        |> assign(:active_sample_index, index)
        |> assign(:sample_title_form, sample_title_form(Map.get(sample, :name, "")))
        |> assign(:sample_entries, sample_entries)
        |> assign(:active_chord_indices, all_chord_indices(sample_entries))
        |> assign(:sample_context, sample_context)
        |> assign(:sample_total_length_mbeats, sample_total_length_mbeats)
        |> assign(:sample_warning, sample_warning)
        |> assign(
          :sample_timeline_static,
          sample_timeline_static_model(
            sample_entries,
            sample_context,
            sample_total_length_mbeats
          )
        )
        |> assign(:render_data, render_data)
        |> assign(:render_scope, :full_sample)
        |> assign(:selected_sample_entry_index, nil)
        |> assign(:player_status, Player.status())
        |> clear_playback_state(true)
        |> assign(:selected_note_key, nil)
        |> assign_detail_content()

      _ ->
        socket
    end
  end

  defp generate_sample_safe(
         sample_entries,
         %SampleContext{} = sample_context,
         sample_total_length_mbeats
       ) do
    try do
      {:ok,
       PerformanceAssembler.generate_sample(sample_entries, sample_context,
         total_length_mbeats: sample_total_length_mbeats
       )}
    rescue
      error in [ArgumentError, RuntimeError] -> {:error, Exception.message(error)}
    end
  end

  defp render_data_and_warning(
         sample_entries,
         %SampleContext{} = sample_context,
         sample_total_length_mbeats
       ) do
    case generate_sample_safe(sample_entries, sample_context, sample_total_length_mbeats) do
      {:ok, data} ->
        {data, cycle_frame_balance_warning(sample_entries, sample_context)}

      {:error, message} ->
        {nil, message}
    end
  end

  defp cycle_frame_balance_warning(sample_entries, %SampleContext{} = sample_context)
       when is_list(sample_entries) do
    current_frame_mbeats = SampleContext.frame_mbeats(sample_context)

    sample_entries
    |> Enum.with_index()
    |> Enum.find_value(fn {entry, entry_index} ->
      cycle_frame_warning_for_entry(entry, entry_index, current_frame_mbeats)
    end)
  end

  defp cycle_frame_warning_for_entry(
         %{
           machine: %DynamicVoicing{params: params},
           timeline_context: %TimelineContext{} = timeline
         },
         entry_index,
         current_frame_mbeats
       )
       when is_struct(params, DynamicVoicingParams) do
    with {:ok, {_cycle_mode, cycle_count}} <- normalize_cycle_direction(params.direction),
         {:ok, inversion_count} <- normalize_cycle_inversion_count(params.number_of_inversions) do
      duration_mbeats = TimelineContext.duration_mbeats(timeline)
      snapped_duration_mbeats = snap_mbeats(duration_mbeats, current_frame_mbeats)
      total_frames = max(div(snapped_duration_mbeats, current_frame_mbeats), 1)
      step_span = inversion_count - 1
      requested_voicings = step_span * 2 * cycle_count + 1

      cond do
        requested_voicings > total_frames ->
          nil

        rem(total_frames, requested_voicings) == 0 ->
          nil

        true ->
          remainder = rem(total_frames, requested_voicings)

          "Cycle timing warning (entry #{entry_index + 1}): #{requested_voicings} voicings are spread over #{total_frames} frames at frame_mbeats=#{current_frame_mbeats} (remainder #{remainder}), so slot lengths are uneven and may look asymmetric."
      end
    else
      _ ->
        nil
    end
  end

  defp cycle_frame_warning_for_entry(_entry, _entry_index, _current_frame_mbeats), do: nil

  defp normalize_cycle_direction({mode, cycle_count})
       when mode in [:cycle_up, :cycle_down] and is_integer(cycle_count) and cycle_count >= 1,
       do: {:ok, {mode, cycle_count}}

  defp normalize_cycle_direction(_other), do: :error

  defp normalize_cycle_inversion_count(inversion_count)
       when is_integer(inversion_count) and inversion_count >= 2,
       do: {:ok, inversion_count}

  defp normalize_cycle_inversion_count(_other), do: :error

  defp snap_mbeats(mbeats, frame_mbeats), do: round(mbeats / frame_mbeats) * frame_mbeats

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

    has_flat_class_root? =
      Enum.any?(
        roots,
        &(&1 in [
            :a_sharp,
            :d_sharp,
            :g_sharp,
            :b_flat,
            :e_flat,
            :a_flat,
            :d_flat,
            :g_flat,
            :c_flat,
            :f_flat
          ])
      )

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

  defp sample_title_form(name) when is_binary(name) do
    to_form(%{"name" => name}, as: :sample_title)
  end

  defp sample_title_form(_name), do: to_form(%{"name" => ""}, as: :sample_title)

  defp normalize_required_string(value, field_name) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, "#{field_name} is required"}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_required_string(_value, field_name), do: {:error, "#{field_name} is required"}

  defp normalize_sample_title(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> {:error, "sample title is required"}
      String.length(trimmed) > 120 -> {:error, "sample title must be at most 120 characters"}
      true -> {:ok, trimmed}
    end
  end

  defp normalize_sample_title(_value), do: {:error, "sample title is required"}

  defp update_sample_name_in_memory(samples, sample_id, new_name)
       when is_list(samples) and is_binary(sample_id) and is_binary(new_name) do
    Enum.map(samples, fn sample ->
      if Map.get(sample, :id) == sample_id do
        Map.put(sample, :name, new_name)
      else
        sample
      end
    end)
  end

  defp sample_context_label(%SampleContext{} = sample_context) do
    {num, den} = sample_context.time_signature
    "#{sample_context.bpm} bpm · #{num}/#{den}"
  end

  defp table_chord_label(%ChordSpec{} = chord_spec) do
    "#{ChordSpec.symbol_label(chord_spec)} · o#{chord_spec.octave} i#{chord_spec.inversion}"
  end

  defp machine_label(machine) do
    machine
    |> Mensch.Machine.id()
    |> Atom.to_string()
  end

  defp machine_icon_name(_machine), do: "hero-cpu-chip"

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

  defp sample_duration_label(
         sample_entries,
         %SampleContext{} = sample_context,
         sample_total_length_mbeats
       )
       when is_list(sample_entries) do
    duration_ms = sample_duration_ms(sample_entries, sample_context, sample_total_length_mbeats)
    minutes = div(duration_ms, 60_000)
    seconds = div(rem(duration_ms, 60_000), 1000)
    millis = rem(duration_ms, 1000)

    "#{minutes}m #{seconds}s #{millis}ms"
  end

  defp sample_duration_ms(
         sample_entries,
         %SampleContext{} = sample_context,
         sample_total_length_mbeats
       )
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

    total_mbeats = max(max_end_mbeat, max(sample_total_length_mbeats || 0, 0))

    SampleContext.mbeats_to_ms(sample_context, total_mbeats)
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

  defp timeline_current_bar_for_playback(socket, playhead_pct) do
    case socket.assigns.sample_timeline_static do
      %{
        source_entries: source_entries,
        total_mbeats: total_mbeats,
        mbeats_per_bar: mbeats_per_bar
      } ->
        timeline_current_bar_index(
          playhead_pct,
          socket.assigns.render_scope,
          source_entries,
          total_mbeats,
          mbeats_per_bar,
          socket.assigns.active_chord_indices
        )

      _ ->
        nil
    end
  end

  defp sample_timeline_static_model(
         sample_entries,
         %SampleContext{} = sample_context,
         sample_total_length_mbeats
       ) do
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

    total_mbeats = max(max(max_end_mbeat, sample_total_length_mbeats || 0), 1)
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
      mbeats_per_bar: mbeats_per_bar,
      row_count: row_count,
      bar_count: bar_count,
      beat_count: beat_count,
      total_mbeats: total_mbeats,
      current_bar_regions: [],
      current_bar: nil
    }
  end

  defp sample_timeline_with_current_bar(
         nil,
         _render_scope,
         _timeline_current_bar,
         _active_chord_indices
       ),
       do: nil

  defp sample_timeline_with_current_bar(
         %{
           source_entries: source_entries,
           total_mbeats: total_mbeats,
           mbeats_per_bar: mbeats_per_bar
         } = model,
         render_scope,
         timeline_current_bar,
         active_chord_indices
       ) do
    current_bar_regions =
      timeline_current_bar_region(
        timeline_current_bar,
        total_mbeats,
        mbeats_per_bar,
        render_scope,
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
    |> Map.put(:current_bar_regions, current_bar_regions)
    |> Map.put(:current_bar, timeline_current_bar)
  end

  defp timeline_entry_state(true, _in_window), do: :active
  defp timeline_entry_state(false, true), do: :inactive_in_window
  defp timeline_entry_state(false, false), do: :inactive_outside_window

  defp timeline_entry_fill(:active, index), do: timeline_color(index)
  defp timeline_entry_fill(:inactive_in_window, _index), do: "#303844"
  defp timeline_entry_fill(:inactive_outside_window, _index), do: "#252c36"

  defp timeline_entry_text_fill(:active), do: "#000000"
  defp timeline_entry_text_fill(:inactive_in_window), do: "#7D8898"
  defp timeline_entry_text_fill(:inactive_outside_window), do: "#626D7D"

  defp timeline_current_bar_index(
         nil,
         _render_scope,
         _entries,
         _total_mbeats,
         _mbeats_per_bar,
         _active_chord_indices
       ),
       do: nil

  defp timeline_current_bar_index(
         playhead_pct,
         :full_sample,
         entries,
         total_mbeats,
         mbeats_per_bar,
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
        bar_index_from_mbeat(total_mbeats * (clamped_pct / 100), total_mbeats, mbeats_per_bar)

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

        bar_index_from_mbeat(absolute_playhead_mbeat, total_mbeats, mbeats_per_bar)
    end
  end

  defp timeline_current_bar_index(
         playhead_pct,
         {:entry, index},
         entries,
         total_mbeats,
         mbeats_per_bar,
         _active_chord_indices
       )
       when is_number(playhead_pct) and is_integer(index) do
    case Enum.at(entries, index) do
      %{start_mbeat: start_mbeat, end_mbeat: end_mbeat} ->
        absolute_playhead_mbeat =
          start_mbeat + max(end_mbeat - start_mbeat, 0) * (max(min(playhead_pct, 100), 0) / 100)

        bar_index_from_mbeat(absolute_playhead_mbeat, total_mbeats, mbeats_per_bar)

      _ ->
        nil
    end
  end

  defp timeline_current_bar_index(
         _playhead_pct,
         _render_scope,
         _entries,
         _total_mbeats,
         _mbeats_per_bar,
         _active_chord_indices
       ),
       do: nil

  defp timeline_current_bar_region(
         timeline_current_bar,
         total_mbeats,
         mbeats_per_bar,
         _render_scope,
         _active_chord_indices
       )
       when is_integer(timeline_current_bar) and timeline_current_bar >= 0 do
    bar_start_mbeat = timeline_current_bar * mbeats_per_bar
    bar_end_mbeat = min(bar_start_mbeat + mbeats_per_bar, total_mbeats)
    x = mbeat_to_svg_x(bar_start_mbeat, total_mbeats)
    width = max(mbeat_to_svg_x(bar_end_mbeat, total_mbeats) - x, 1)

    [%{x: x, width: width}]
  end

  defp timeline_current_bar_region(
         _timeline_current_bar,
         _total_mbeats,
         _mbeats_per_bar,
         _render_scope,
         _active_chord_indices
       ),
       do: []

  defp bar_index_from_mbeat(playhead_mbeat, total_mbeats, mbeats_per_bar)
       when is_number(playhead_mbeat) do
    clamped_mbeat = max(min(playhead_mbeat, total_mbeats), 0)
    bar_count = max(div(total_mbeats + mbeats_per_bar - 1, mbeats_per_bar), 1)

    clamped_mbeat
    |> floor()
    |> div(mbeats_per_bar)
    |> min(bar_count - 1)
  end

  defp active_bar_marker?(bar_number, current_bar)
       when is_integer(bar_number) and is_integer(current_bar) and current_bar >= 0,
       do: bar_number == current_bar + 1

  defp active_bar_marker?(_bar_number, _current_bar), do: false

  defp timeline_color(index) do
    Enum.at(@chart_colors, rem(index, length(@chart_colors)))
  end

  defp entry_color_dot_style(index) do
    color = timeline_color(index)

    "background-color: #{color};"
  end

  defp short_chord_label(%ChordSpec{} = chord_spec) do
    ChordSpec.symbol_label(chord_spec)
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
        |> Enum.map(fn %{
                         start_mbeat: start_mbeat,
                         end_mbeat: end_mbeat,
                         label: label,
                         note_on_velocity: note_on_velocity,
                         note_off_velocity: note_off_velocity
                       } ->
          left_pct = start_mbeat / total_mbeats * 100
          width_pct = max((end_mbeat - start_mbeat) / total_mbeats * 100, 0.5)
          is_selected = note_selected?({channel, midi_note_number}, selected_note_key)

          in_active_chords =
            note_in_active_chords?(
              series_key,
              active_chord_indices
            )

          style =
            "left: #{Float.round(left_pct * 1.0, 2)}%; " <>
              "width: #{Float.round(width_pct * 1.0, 2)}%; " <>
              "background-color: #{note_matrix_velocity_color(Map.fetch!(colors, series_key), note_on_velocity, is_selected, in_active_chords)};"

          note_on_marker_style =
            note_matrix_velocity_marker_style(
              Map.fetch!(colors, series_key),
              note_on_velocity
            )

          note_off_marker_style =
            note_matrix_velocity_marker_style(
              Map.fetch!(colors, series_key),
              note_off_velocity
            )

          %{
            series_key: series_key,
            channel: channel,
            midi_note: midi_note_number,
            label: label,
            active: is_selected,
            note_on_velocity: note_on_velocity,
            note_off_velocity: note_off_velocity,
            style: style,
            note_on_marker_style: note_on_marker_style,
            note_off_marker_style: note_off_marker_style
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
                    active: segment.active,
                    note_on_velocity: Map.get(segment, :note_on_velocity, 0),
                    note_off_velocity: Map.get(segment, :note_off_velocity, 0),
                    note_on_marker_style:
                      Map.get(
                        segment,
                        :note_on_marker_style,
                        "background-color: rgba(255, 255, 255, 0.35);"
                      ),
                    note_off_marker_style:
                      Map.get(
                        segment,
                        :note_off_marker_style,
                        "background-color: rgba(255, 255, 255, 0.35);"
                      )
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
        note_on_velocity = note_matrix_note_on_velocity(note)

        cond do
          note.note_on and is_nil(open) ->
            {acc,
             %{
               start_mbeat: at_mbeat,
               label: label,
               note_on_velocity: note_on_velocity,
               note_off_velocity: 0
             }}

          note.note_on and not is_nil(open) ->
            closed =
              open
              |> Map.put(:end_mbeat, at_mbeat)
              |> Map.put(:note_off_velocity, 0)

            {[closed | acc],
             %{
               start_mbeat: at_mbeat,
               label: label,
               note_on_velocity: note_on_velocity,
               note_off_velocity: 0
             }}

          note.note_off and not is_nil(open) ->
            closed =
              open
              |> Map.put(:end_mbeat, at_mbeat)
              |> Map.put(:note_off_velocity, note_matrix_note_off_velocity(note))

            {[closed | acc], nil}

          true ->
            {acc, open}
        end
      end)

    segments =
      if is_nil(open_segment) do
        segments
      else
        [
          open_segment
          |> Map.put(:end_mbeat, total_mbeats)
          |> Map.put(:note_off_velocity, 0)
          | segments
        ]
      end

    segments
    |> Enum.reverse()
    |> Enum.filter(fn segment -> segment.end_mbeat >= segment.start_mbeat end)
  end

  defp note_matrix_note_on_velocity(note) do
    note
    |> Map.get(:note_on_velocity, 0)
    |> clamp_u7()
  end

  defp note_matrix_note_off_velocity(note) do
    note
    |> Map.get(:note_off_velocity, 0)
    |> clamp_u7()
  end

  defp note_matrix_velocity_color(base_color, velocity, is_selected, in_active_chords) do
    {red, green, blue} = color_rgb_tuple(base_color)
    velocity_ratio = velocity / 127

    focus_alpha =
      cond do
        not in_active_chords -> 0.16
        is_selected -> 0.92
        true -> 0.64
      end

    velocity_alpha = 0.35 + velocity_ratio * 0.65
    alpha = Float.round(focus_alpha * velocity_alpha, 2)

    "rgba(#{red}, #{green}, #{blue}, #{alpha})"
  end

  defp note_matrix_velocity_marker_style(base_color, velocity) do
    {red, green, blue} = color_rgb_tuple(base_color)
    darken_factor = 0.4
    dark_red = round(red * darken_factor)
    dark_green = round(green * darken_factor)
    dark_blue = round(blue * darken_factor)

    ratio = velocity / 127
    filled_degrees = Float.round(ratio * 360, 1)

    "background: conic-gradient(rgb(#{red}, #{green}, #{blue}) 0deg #{filled_degrees}deg, rgb(#{dark_red}, #{dark_green}, #{dark_blue}) #{filled_degrees}deg 360deg);"
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

  defp color_rgb_tuple("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    {r_i, _} = Integer.parse(r, 16)
    {g_i, _} = Integer.parse(g, 16)
    {b_i, _} = Integer.parse(b, 16)
    {r_i, g_i, b_i}
  end

  defp color_rgb_tuple("rgba(" <> rest) do
    [r, g, b | _] =
      rest
      |> String.trim_trailing(")")
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    {String.to_integer(r), String.to_integer(g), String.to_integer(b)}
  end

  defp color_rgb_tuple("rgb(" <> rest) do
    [r, g, b] =
      rest
      |> String.trim_trailing(")")
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    {String.to_integer(r), String.to_integer(g), String.to_integer(b)}
  end

  defp color_rgb_tuple(_color), do: {160, 160, 160}

  defp clamp_u7(value) when is_integer(value), do: value |> max(0) |> min(127)
  defp clamp_u7(value) when is_float(value), do: value |> round() |> clamp_u7()
  defp clamp_u7(_value), do: 0

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
        |> assign(:pressure_axis, pressure_slide_axis())
        |> assign(:slide_axis, pressure_slide_axis())
        |> assign(:bend_axis, bend_axis({-1.0, 1.0}))
        |> assign(:debug_rows, [])
        |> assign(:note_matrix, [])
        |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
        |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})

      %{frames: frames, duration_ms: duration_ms} ->
        full_total_mbeats =
          detail_total_mbeats(frames, duration_ms, socket.assigns.sample_context)

        {window_start_mbeat, window_end_mbeat} =
          case socket.assigns.render_scope do
            :full_sample ->
              {0, full_total_mbeats}

            _other_scope ->
              selected_scope_mbeats(
                socket.assigns.sample_entries,
                socket.assigns.sample_context,
                socket.assigns.active_chord_indices,
                full_total_mbeats
              )
          end

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
        |> assign(:pressure_axis, pressure_slide_axis())
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
        |> assign(:slide_axis, pressure_slide_axis())
        |> assign(:bend_axis, bend_axis(value_range(scoped_frames)))
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

  # Bend's absolute range is intentionally tiny, so it gets its own
  # dynamic min/max instead of
  # being squashed flat against a fixed +/-1.0 scale.
  defp value_range(frames) do
    values = for frame <- frames, note <- frame.notes, do: note.bend

    case Enum.min_max(values) do
      {same, same} -> {same - 0.0001, same + 0.0001}
      {min_v, max_v} -> {min_v, max_v}
    end
  end

  defp pressure_slide_axis do
    %{
      min: 0,
      max: 127,
      ticks: [
        %{value: 0, label: "0"},
        %{value: 32, label: "32"},
        %{value: 64, label: "64"},
        %{value: 96, label: "96"},
        %{value: 127, label: "127"}
      ]
    }
  end

  defp bend_axis({min_v, max_v}) do
    steps = 4

    ticks =
      for step_index <- 0..steps do
        value = min_v + (max_v - min_v) * (step_index / steps)
        %{value: value, label: format_bend_tick(value)}
      end

    %{min: min_v, max: max_v, ticks: ticks}
  end

  defp format_bend_tick(value) when is_number(value) do
    value
    |> Float.round(4)
    |> :erlang.float_to_binary(decimals: 4)
    |> String.replace(~r/0+$/, "")
    |> String.replace(~r/\.$/, "")
  end
end
