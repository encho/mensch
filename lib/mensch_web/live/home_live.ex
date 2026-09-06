defmodule MenschWeb.HomeLive do
  @moduledoc """
  Minimal UI: RENDER precomputes the full MPE performance for a
  hardcoded C4 maj7 chord (see `Mensch.Render`), showing its pressure/
  slide/bend curves as line charts. PLAY then dispatches that
  precomputed data in real time to the connected MIDI output (e.g. an
  Osmose); STOP silences it immediately.
  """

  use MenschWeb, :live_view

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Player
  alias Mensch.Render
  alias Mensch.SongContext

  @refresh_interval_ms 100
  @chart_colors ["#39FF14", "#00E5FF", "#FF4DFF", "#FFD400", "#FF5F1F", "#7DFF7A"]

  @impl true
  def mount(_params, _session, socket) do
    song_entries = Render.default_song_entries()
    song_context = Render.default_song_context()

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:render_data, nil)
      |> assign(:player_status, Player.status())
      |> assign(:play_started_at, nil)
      |> assign(:playhead_pct, nil)
      |> assign(:song_entries, song_entries)
      |> assign(:song_context, song_context)
      |> assign(:view_modal_open, false)
      |> assign(:view_title, nil)
      |> assign(:render_scope, :full_song)
      |> assign(:loop_full_song, false)
      |> assign(:manual_stop, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("view_full_song", _params, socket) do
    entries = socket.assigns.song_entries
    song_context = socket.assigns.song_context
    render_data = Render.generate_song(entries, song_context)

    {:noreply,
     socket
     |> assign(:render_data, render_data)
     |> assign(:view_title, "Full Song")
     |> assign(:render_scope, :full_song)
     |> assign(:view_modal_open, true)}
  end

  def handle_event("play_full_song", _params, socket) do
    entries = socket.assigns.song_entries
    song_context = socket.assigns.song_context
    render_data = Render.generate_song(entries, song_context)

    {:noreply,
     socket
     |> assign(:render_data, render_data)
     |> assign(:render_scope, :full_song)
     |> assign(:manual_stop, false)
     |> start_playback(render_data)}
  end

  def handle_event("toggle_loop_full_song", _params, socket) do
    {:noreply, update(socket, :loop_full_song, &(!&1))}
  end

  def handle_event("view_entry", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, ""} ->
        case Enum.at(socket.assigns.song_entries, index) do
          %{chord_spec: %ChordSpec{} = chord_spec} ->
            render_data = Render.generate(chord_spec)

            {:noreply,
             socket
             |> assign(:render_data, render_data)
             |> assign(:view_title, chord_label(chord_spec))
             |> assign(:render_scope, {:entry, index})
             |> assign(:view_modal_open, true)}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("play_entry", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, ""} ->
        case Enum.at(socket.assigns.song_entries, index) do
          %{chord_spec: %ChordSpec{} = chord_spec} ->
            render_data = Render.generate(chord_spec)

            {:noreply,
             socket
             |> assign(:render_data, render_data)
             |> assign(:render_scope, {:entry, index})
             |> assign(:manual_stop, false)
             |> start_playback(render_data)}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_view", _params, socket) do
    {:noreply, assign(socket, :view_modal_open, false)}
  end

  def handle_event("play", _params, %{assigns: %{render_data: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("play", _params, socket) do
    {:noreply,
     socket |> assign(:manual_stop, false) |> start_playback(socket.assigns.render_data)}
  end

  def handle_event("stop", _params, socket) do
    Player.stop()

    socket =
      socket
      |> assign(:player_status, Player.status())
      |> assign(:play_started_at, nil)
      |> assign(:playhead_pct, nil)
      |> assign(:manual_stop, true)

    {:noreply, socket}
  end

  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_info(:refresh_player, socket) do
    status = Player.status()

    socket =
      socket
      |> assign(:player_status, status)
      |> assign(
        :playhead_pct,
        playhead_pct(status, socket.assigns.play_started_at, socket.assigns.render_data)
      )

    cond do
      status == :playing ->
        Process.send_after(self(), :refresh_player, @refresh_interval_ms)
        {:noreply, socket}

      loop_full_song?(socket) ->
        {:noreply,
         socket |> assign(:manual_stop, false) |> start_playback(socket.assigns.render_data)}

      true ->
        {:noreply, assign(socket, :manual_stop, false)}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      case assigns.render_data do
        nil ->
          assigns
          |> assign(:pressure_chart, [])
          |> assign(:slide_chart, [])
          |> assign(:bend_chart, [])
          |> assign(:debug_rows, [])
          |> assign(:note_matrix, [])
          |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
          |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})
          |> assign(:detail_chart_playhead_x, nil)
          |> assign(:detail_matrix_playhead_pct, nil)

        %{music: music, duration_ms: duration_ms} ->
          projection =
            detail_projection_model(
              assigns.song_entries,
              assigns.song_context,
              assigns.render_scope,
              duration_ms
            )

          assigns
          |> assign(
            :pressure_chart,
            build_chart(
              music,
              :pressure,
              {0, 127},
              assigns.render_scope,
              assigns.song_context,
              projection
            )
          )
          |> assign(
            :slide_chart,
            build_chart(
              music,
              :slide,
              {0, 127},
              assigns.render_scope,
              assigns.song_context,
              projection
            )
          )
          |> assign(
            :bend_chart,
            build_chart(
              music,
              :bend,
              value_range(music),
              assigns.render_scope,
              assigns.song_context,
              projection
            )
          )
          |> assign(:debug_rows, debug_rows(music))
          |> assign(
            :note_matrix,
            build_note_matrix(music, assigns.render_scope, assigns.song_context, projection)
          )
          |> assign(:chart_grid, chart_grid_model(assigns.song_context, projection.total_ticks))
          |> assign(
            :note_matrix_grid,
            note_matrix_grid_model(assigns.song_context, projection.total_ticks)
          )
          |> assign(
            :detail_chart_playhead_x,
            detail_playhead_x(assigns.playhead_pct, projection, 600)
          )
          |> assign(
            :detail_matrix_playhead_pct,
            detail_playhead_pct(assigns.playhead_pct, projection)
          )
      end

    assigns =
      assign(
        assigns,
        :song_timeline,
        song_timeline_model(
          assigns.song_entries,
          assigns.song_context,
          assigns.playhead_pct,
          assigns.render_scope
        )
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status}>
      <div class="mx-auto max-w-6xl space-y-6">
        <div id="render-section" class="space-y-4 border border-white/15 p-4">
          <div class="text-[11px] uppercase tracking-wide text-white/40">Render Context</div>

          <div class="font-mono text-[11px] text-white/55">
            SongCtx: {song_context_label(@song_context)}
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              id="toggle-loop-full-song"
              phx-click="toggle_loop_full_song"
              aria-pressed={@loop_full_song}
              class={[
                "border px-3 py-1.5 text-[11px] uppercase tracking-wide transition-colors duration-150",
                (@loop_full_song &&
                   "border-emerald-400 text-emerald-300 ring-1 ring-emerald-500/70") ||
                  "border-white/30 text-white/70 hover:border-white hover:text-white"
              ]}
            >
              Loop {if(@loop_full_song, do: "On", else: "Off")}
            </button>
            <button
              type="button"
              id="view-full-song"
              phx-click="view_full_song"
              class="border border-white/30 px-3 py-1.5 text-[11px] uppercase tracking-wide text-white/70 transition-colors duration-150 hover:border-white hover:text-white"
            >
              View
            </button>
            <button
              type="button"
              id="play-full-song"
              aria-label="Play full song"
              phx-click="play_full_song"
              class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-white/75 ring-1 ring-white/20 transition-colors duration-150 hover:border-white/70 hover:text-white hover:ring-white/40"
            >
              <.icon name="hero-play-solid" class="size-4" />
            </button>
            <button
              type="button"
              id="stop-full-song"
              aria-label="Stop full song"
              phx-click="stop"
              class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-white/75 ring-1 ring-white/20 transition-colors duration-150 hover:border-white/70 hover:text-white hover:ring-white/40"
            >
              <.icon name="hero-stop-solid" class="size-4" />
            </button>
          </div>

          <div class="overflow-x-auto border border-white/10">
            <table class="w-full min-w-[860px] text-left font-mono text-[11px]">
              <thead>
                <tr class="border-b border-white/10 text-white/40">
                  <th class="px-2 py-1.5 font-normal">ChordSpec</th>
                  <th class="px-2 py-1.5 font-normal">Machine</th>
                  <th class="px-2 py-1.5 font-normal">Start</th>
                  <th class="px-2 py-1.5 font-normal">Duration</th>
                  <th class="px-2 py-1.5 font-normal text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{entry, index} <- Enum.with_index(@song_entries)} class="text-white/80">
                  <td class="px-2 py-1.5 text-white">
                    <div class="flex items-center gap-2">
                      <span
                        class="inline-block size-2.5 rounded-full"
                        style={entry_color_dot_style(index)}
                      ></span>
                      <span>{chord_label(entry.chord_spec)}</span>
                    </div>
                  </td>
                  <td class="px-2 py-1.5">{machine_label(entry.machine_module)}</td>
                  <td class="px-2 py-1.5 align-top">
                    <div class="leading-tight text-white">
                      {start_label_primary(@song_context, entry.timeline_context.start_beat)}
                    </div>
                    <div class="leading-tight text-white/40">
                      {start_label_secondary(@song_context, entry.timeline_context.start_beat)}
                    </div>
                  </td>
                  <td class="px-2 py-1.5 align-top">
                    <div class="leading-tight text-white">
                      {duration_label_primary(@song_context, entry.timeline_context.duration_ticks)}
                    </div>
                    <div class="leading-tight text-white/40">
                      {duration_label_secondary(entry.timeline_context.duration_ticks)}
                    </div>
                  </td>
                  <td class="px-2 py-1.5 text-right">
                    <div class="flex items-center justify-end gap-2">
                      <button
                        type="button"
                        id={"view-entry-#{index}"}
                        phx-click="view_entry"
                        phx-value-index={index}
                        class="border border-white/30 px-3 py-1.5 text-white/70 transition-colors duration-150 hover:border-white hover:text-white"
                      >
                        View
                      </button>
                      <button
                        type="button"
                        id={"play-entry-#{index}"}
                        aria-label={"Play #{chord_label(entry.chord_spec)}"}
                        phx-click="play_entry"
                        phx-value-index={index}
                        class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-white/75 ring-1 ring-white/20 transition-colors duration-150 hover:border-white/70 hover:text-white hover:ring-white/40"
                      >
                        <.icon name="hero-play-solid" class="size-4" />
                      </button>
                      <button
                        type="button"
                        id={"stop-entry-#{index}"}
                        aria-label={"Stop #{chord_label(entry.chord_spec)}"}
                        phx-click="stop"
                        class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-white/75 ring-1 ring-white/20 transition-colors duration-150 hover:border-white/70 hover:text-white hover:ring-white/40"
                      >
                        <.icon name="hero-stop-solid" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.song_timeline model={@song_timeline} />
        </div>
      </div>
      <div
        :if={@view_modal_open and @render_data}
        id="render-view-modal"
        class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4"
      >
        <div class="w-full max-w-6xl space-y-4 border border-white/20 bg-black p-4">
          <div class="flex items-center justify-between border-b border-white/10 pb-2">
            <div class="text-sm uppercase tracking-wide text-white/75">{@view_title || "View"}</div>
            <button
              type="button"
              id="close-view-modal"
              phx-click="close_view"
              class="border border-white/30 px-2 py-1 text-[11px] uppercase tracking-wide text-white/70 transition-colors duration-150 hover:border-white hover:text-white"
            >
              Close
            </button>
          </div>

          <div class="font-mono text-[11px] text-white/50">
            {@render_data.bpm} bpm · {elem(@render_data.time_signature, 0)}/{elem(
              @render_data.time_signature,
              1
            )} · {@render_data.granularity_ms}ms ticks · {@render_data.duration_ms}ms · {length(
              @render_data.music
            )} frames
          </div>

          <div id="debug-frames" class="border border-white/10">
            <div class="border-b border-white/10 px-3 py-1.5 text-[11px] uppercase tracking-wide text-white/40">
              All frames
            </div>
            <div class="max-h-48 overflow-y-auto">
              <table class="w-full text-left font-mono text-[11px]">
                <thead class="sticky top-0 bg-black">
                  <tr class="border-b border-white/10 text-white/40">
                    <th class="px-3 py-1.5 font-normal">ms</th>
                    <th class="px-3 py-1.5 font-normal">note</th>
                    <th class="px-3 py-1.5 font-normal">ch</th>
                    <th class="px-3 py-1.5 font-normal">phase</th>
                    <th class="px-3 py-1.5 font-normal">on</th>
                    <th class="px-3 py-1.5 font-normal">off</th>
                    <th class="px-3 py-1.5 font-normal">pressure</th>
                    <th class="px-3 py-1.5 font-normal">bend</th>
                    <th class="px-3 py-1.5 font-normal">slide</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={row <- @debug_rows}
                    class="border-b border-white/5 text-white/70 last:border-0"
                  >
                    <td class="px-3 py-1.5">{row.at_ms}</td>
                    <td class="px-3 py-1.5 text-white">{row.note_name}{row.octave}</td>
                    <td class="px-3 py-1.5">{row.channel}</td>
                    <td class="px-3 py-1.5">{row.phase}</td>
                    <td class="px-3 py-1.5">{row.note_on}</td>
                    <td class="px-3 py-1.5">{row.note_off}</td>
                    <td class="px-3 py-1.5">{row.pressure}</td>
                    <td class="px-3 py-1.5">{format_bend(row.bend)}</td>
                    <td class="px-3 py-1.5">{row.slide}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div id="note-matrix" class="border border-white/10">
            <div class="border-b border-white/10 px-3 py-1.5 text-[11px] uppercase tracking-wide text-white/40">
              Note matrix
            </div>
            <div class="relative py-2">
              <div
                :for={x <- @note_matrix_grid.subbeat_pcts}
                class="pointer-events-none absolute inset-y-0 z-0 w-px bg-white/5"
                style={"left: #{x}%;"}
              >
              </div>
              <div
                :for={x <- @note_matrix_grid.beat_pcts}
                class="pointer-events-none absolute inset-y-0 z-0 w-px bg-white/10"
                style={"left: #{x}%;"}
              >
              </div>
              <div
                :for={x <- @note_matrix_grid.bar_pcts}
                class="pointer-events-none absolute inset-y-0 z-0 w-px bg-white/25"
                style={"left: #{x}%;"}
              >
              </div>
              <div
                :if={not is_nil(@detail_matrix_playhead_pct)}
                class="pointer-events-none absolute inset-y-0 z-20 w-px bg-white/70"
                style={"left: #{@detail_matrix_playhead_pct}%;"}
              >
              </div>
              <div
                :for={{row, index} <- Enum.with_index(@note_matrix)}
                class={[
                  "relative z-10 flex h-2.5 items-center border-b border-white/20 last:border-0",
                  rem(index, 2) == 0 && "bg-white/[0.03]"
                ]}
              >
                <div
                  :for={style <- row.styles}
                  class="absolute inset-y-0"
                  style={style}
                >
                </div>
                <span class={[
                  "relative z-10 px-1 font-mono text-[5px] uppercase",
                  (Enum.empty?(row.styles) && "text-white/30") || "text-white"
                ]}>
                  {row.label}
                </span>
              </div>
            </div>
            <div class="flex justify-between px-3 pb-2 pt-1 font-mono text-[10px] text-white/30">
              <span>0ms</span>
              <span>{@render_data.duration_ms}ms</span>
            </div>
          </div>

          <.chart
            title="Pressure"
            chart={@pressure_chart}
            grid={@chart_grid}
            playhead_x={@detail_chart_playhead_x}
          />
          <.chart
            title="Slide (Aftertouch)"
            chart={@slide_chart}
            grid={@chart_grid}
            playhead_x={@detail_chart_playhead_x}
          />
          <.chart
            title="Bend (Vibrato)"
            chart={@bend_chart}
            grid={@chart_grid}
            playhead_x={@detail_chart_playhead_x}
          />

          <div class="flex justify-center gap-3">
            <button
              type="button"
              id="play-button"
              aria-label="Play on Osmose"
              phx-click="play"
              class={[
                "flex size-14 items-center justify-center border border-zinc-500 bg-transparent transition-colors duration-150",
                (playing?(@player_status) && "text-white/20 ring-1 ring-white/10") ||
                  "text-white/75 ring-1 ring-white/20 hover:border-white/70 hover:text-white hover:ring-white/40",
                "disabled:cursor-not-allowed"
              ]}
              disabled={playing?(@player_status)}
            >
              <.icon name="hero-play-solid" class="size-6" />
            </button>
            <button
              type="button"
              id="stop-button"
              aria-label="Stop"
              phx-click="stop"
              class={[
                "flex size-14 items-center justify-center border border-zinc-500 bg-transparent transition-colors duration-150",
                (playing?(@player_status) &&
                   "text-white/75 ring-1 ring-white/20 hover:border-white/70 hover:text-white hover:ring-white/40") ||
                  "text-white/20 ring-1 ring-white/10",
                "disabled:cursor-not-allowed"
              ]}
              disabled={!playing?(@player_status)}
            >
              <.icon name="hero-stop-solid" class="size-6" />
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :model, :map, required: true

  defp song_timeline(assigns) do
    ~H"""
    <div id="song-timeline" class="space-y-2 border border-white/10 p-3">
      <div class="flex items-center justify-between font-mono text-[11px] text-white/45">
        <span class="uppercase tracking-wide">Timeline</span>
        <span>
          {@model.row_count} rows · {@model.bar_count} bars · {@model.beat_count} beats · {@model.total_ticks} ticks
        </span>
      </div>

      <svg
        viewBox={"0 0 #{@model.svg_width} #{@model.svg_height}"}
        class="w-full border border-white/10 bg-black/40"
      >
        <line
          :for={x <- @model.subbeat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="#ffffff"
          stroke-opacity="0.06"
          stroke-width="1"
        />
        <line
          :for={x <- @model.beat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="#ffffff"
          stroke-opacity="0.14"
          stroke-width="1"
        />
        <line
          :for={{x, bar_number} <- @model.bar_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="#ffffff"
          stroke-opacity="0.32"
          stroke-width="1.2"
        />

        <rect
          :for={lane <- @model.lanes}
          x="0"
          y={lane.y}
          width={@model.svg_width}
          height={lane.height}
          fill="#ffffff"
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
          fill="#ffffff"
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
          fill="#ffffff"
          fill-opacity="0.65"
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
          stroke="#ffffff"
          stroke-opacity="0.75"
          stroke-width="1.5"
        />
      </svg>

      <div class="flex items-center justify-between font-mono text-[10px] text-white/35">
        <span>0</span>
        <span>{@model.total_ticks} ticks</span>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :chart, :list, required: true
  attr :grid, :map, required: true
  attr :playhead_x, :any, default: nil

  defp chart(assigns) do
    ~H"""
    <div>
      <div class="mb-1 text-[11px] uppercase tracking-wide text-white/40">{@title}</div>
      <svg viewBox="0 0 600 120" class="w-full border border-white/10 bg-black">
        <line
          :for={x <- @grid.subbeat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2="120"
          stroke="#ffffff"
          stroke-opacity="0.05"
          stroke-width="1"
        />
        <line
          :for={x <- @grid.beat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2="120"
          stroke="#ffffff"
          stroke-opacity="0.12"
          stroke-width="1"
        />
        <line
          :for={x <- @grid.bar_xs}
          x1={x}
          y1="0"
          x2={x}
          y2="120"
          stroke="#ffffff"
          stroke-opacity="0.26"
          stroke-width="1.2"
        />
        <polyline
          :for={series <- @chart}
          points={series.points}
          fill="none"
          stroke={series.color}
          stroke-width="1.5"
        />
        <line
          :if={not is_nil(@playhead_x)}
          x1={@playhead_x}
          x2={@playhead_x}
          y1="0"
          y2="120"
          stroke="#ffffff"
          stroke-opacity="0.7"
          stroke-width="1"
        />
      </svg>
    </div>
    """
  end

  defp playing?(player_status), do: player_status == :playing

  defp start_playback(socket, render_data) do
    Player.play(render_data)
    Process.send_after(self(), :refresh_player, @refresh_interval_ms)

    play_started_at = System.monotonic_time(:millisecond)

    socket
    |> assign(:player_status, Player.status())
    |> assign(:play_started_at, play_started_at)
    |> assign(:playhead_pct, playhead_pct(:playing, play_started_at, render_data))
  end

  defp loop_full_song?(socket) do
    socket.assigns.loop_full_song and
      not socket.assigns.manual_stop and
      not is_nil(socket.assigns.render_data)
  end

  # How far (0-100) through the performance playback currently is, for
  # drawing a moving crosshair over the charts/note matrix - `nil`
  # (hides the crosshair) unless actually mid-playback. Computed and
  # assigned directly on the socket each `:refresh_player` tick (not
  # derived inside `render/1`), so its per-tick change is reliably
  # picked up and pushed to the client.
  defp playhead_pct(:playing, play_started_at, %{duration_ms: duration_ms})
       when not is_nil(play_started_at) and duration_ms > 0 do
    (System.monotonic_time(:millisecond) - play_started_at)
    |> max(0)
    |> min(duration_ms)
    |> Kernel./(duration_ms)
    |> Kernel.*(100)
  end

  defp playhead_pct(_player_status, _play_started_at, _render_data), do: nil

  # Flattens every frame (one row per note) for a raw, at-a-glance table
  # of exactly what the note-on/pressure/bend/slide sequence looks like
  # across the whole chord performance.
  defp debug_rows(music) do
    Enum.flat_map(music, fn frame ->
      Enum.map(frame.notes, &Map.put(&1, :at_ms, frame.at_ms))
    end)
  end

  defp format_bend(bend), do: Float.round(bend * 1.0, 5)

  defp song_context_label(%SongContext{} = song_context) do
    {num, den} = song_context.time_signature
    "#{song_context.bpm} bpm · #{num}/#{den} · ppq #{song_context.ppq}"
  end

  defp chord_label(%ChordSpec{} = chord_spec) do
    root = chord_spec.root |> Atom.to_string() |> String.replace("_sharp", "#") |> String.upcase()
    modifier = chord_spec.modifier |> Atom.to_string()
    "#{root} #{modifier} · Oct #{chord_spec.octave} · Inv #{chord_spec.inversion}"
  end

  defp machine_label(machine_module) when is_atom(machine_module) do
    machine_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp start_label_primary(%SongContext{} = song_context, %BeatPosition{} = start_beat) do
    tick = SongContext.position_to_tick(song_context, start_beat)
    ms = SongContext.ticks_to_ms(song_context, tick)

    "bar #{start_beat.bar} · beat #{start_beat.beat} · #{SongContext.format_timestamp(ms)}"
  end

  defp start_label_secondary(%SongContext{} = song_context, %BeatPosition{} = start_beat) do
    tick = SongContext.position_to_tick(song_context, start_beat)
    "tick #{tick}"
  end

  defp duration_label_primary(%SongContext{} = song_context, duration_ticks) do
    ticks_per_bar = SongContext.ticks_per_bar(song_context)
    ticks_per_beat = SongContext.ticks_per_beat(song_context)
    duration_ms = SongContext.ticks_to_ms(song_context, duration_ticks)
    duration_s = duration_ms / 1000

    musical =
      cond do
        rem(duration_ticks, ticks_per_bar) == 0 ->
          bars = div(duration_ticks, ticks_per_bar)
          "#{bars} bar"

        rem(duration_ticks, ticks_per_beat) == 0 ->
          beats = div(duration_ticks, ticks_per_beat)
          "#{beats} beats"

        true ->
          beats = div(duration_ticks, ticks_per_beat)
          ticks = rem(duration_ticks, ticks_per_beat)
          "#{beats} beats + #{ticks} ticks"
      end

    "#{musical} · #{:erlang.float_to_binary(duration_s, decimals: 2)}s"
  end

  defp duration_label_secondary(duration_ticks) do
    "#{duration_ticks} ticks"
  end

  defp song_timeline_model(
         song_entries,
         %SongContext{} = song_context,
         playhead_pct,
         render_scope
       ) do
    svg_width = 1000
    lane_height = 22
    lane_gap = 8
    lanes_top = 22
    lanes_bottom = 12

    ticks_per_bar = SongContext.ticks_per_bar(song_context)
    ticks_per_beat = SongContext.ticks_per_beat(song_context)
    ticks_per_subbeat = max(div(ticks_per_beat, 4), 1)

    entries =
      Enum.map(song_entries, fn %{chord_spec: chord_spec, timeline_context: timeline_context} ->
        start_tick = SongContext.position_to_tick(song_context, timeline_context.start_beat)
        end_tick = start_tick + timeline_context.duration_ticks

        %{label: short_chord_label(chord_spec), start_tick: start_tick, end_tick: end_tick}
      end)

    max_end_tick =
      case entries do
        [] -> ticks_per_bar * 2
        _ -> entries |> Enum.map(& &1.end_tick) |> Enum.max()
      end

    bar_count = max(div(max_end_tick + ticks_per_bar - 1, ticks_per_bar), 2)
    total_ticks = bar_count * ticks_per_bar
    beat_count = bar_count * SongContext.beats_per_bar(song_context)
    total_ticks = max(total_ticks, 1)
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
      |> Enum.map(fn {%{label: label, start_tick: start_tick, end_tick: end_tick}, index} ->
        lane_y = lanes_top + index * (lane_height + lane_gap)
        x = tick_to_svg_x(start_tick, total_ticks)
        width = max(tick_to_svg_x(end_tick, total_ticks) - x, 8)

        %{
          label: label,
          x: x,
          y: lane_y + 1,
          width: width,
          height: lane_height - 2,
          text_y: lane_y + 14,
          fill: timeline_color(index)
        }
      end)

    playhead_x = timeline_playhead_x(playhead_pct, render_scope, entries, total_ticks)

    %{
      svg_width: svg_width,
      svg_height: svg_height,
      lanes: lanes,
      entries: entries_with_geometry,
      playhead_x: playhead_x,
      subbeat_xs: timeline_xs(total_ticks, ticks_per_subbeat),
      beat_xs: timeline_xs(total_ticks, ticks_per_beat),
      bar_xs:
        timeline_xs(total_ticks, ticks_per_bar)
        |> Enum.with_index(1),
      row_count: row_count,
      bar_count: bar_count,
      beat_count: beat_count,
      total_ticks: total_ticks
    }
  end

  defp timeline_playhead_x(nil, _render_scope, _entries, _total_ticks), do: nil

  defp timeline_playhead_x(playhead_pct, :full_song, _entries, total_ticks)
       when is_number(playhead_pct) do
    tick_to_svg_x(total_ticks * (playhead_pct / 100), total_ticks)
  end

  defp timeline_playhead_x(playhead_pct, {:entry, index}, entries, total_ticks)
       when is_number(playhead_pct) and is_integer(index) do
    case Enum.at(entries, index) do
      %{start_tick: start_tick, end_tick: end_tick} ->
        start_x = tick_to_svg_x(start_tick, total_ticks)
        end_x = tick_to_svg_x(end_tick, total_ticks)
        Float.round(start_x + (end_x - start_x) * (playhead_pct / 100), 2)

      _ ->
        nil
    end
  end

  defp timeline_playhead_x(_playhead_pct, _render_scope, _entries, _total_ticks), do: nil

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

  defp timeline_xs(total_ticks, step) do
    0..total_ticks//step
    |> Enum.map(&tick_to_svg_x(&1, total_ticks))
  end

  defp tick_to_svg_x(tick, total_ticks) do
    tick
    |> Kernel./(total_ticks)
    |> Kernel.*(1000)
    |> Float.round(2)
  end

  defp chart_grid_model(%SongContext{} = song_context, total_ticks) do
    width = 600
    ticks_per_bar = SongContext.ticks_per_bar(song_context)
    ticks_per_beat = SongContext.ticks_per_beat(song_context)
    ticks_per_subbeat = max(div(ticks_per_beat, 4), 1)
    total_ticks = max(total_ticks, 1)

    %{
      subbeat_xs: chart_grid_xs(total_ticks, ticks_per_subbeat, width),
      beat_xs: chart_grid_xs(total_ticks, ticks_per_beat, width),
      bar_xs: chart_grid_xs(total_ticks, ticks_per_bar, width)
    }
  end

  defp note_matrix_grid_model(%SongContext{} = song_context, total_ticks) do
    ticks_per_bar = SongContext.ticks_per_bar(song_context)
    ticks_per_beat = SongContext.ticks_per_beat(song_context)
    ticks_per_subbeat = max(div(ticks_per_beat, 4), 1)
    total_ticks = max(total_ticks, 1)

    %{
      subbeat_pcts: timeline_pct_marks(total_ticks, ticks_per_subbeat),
      beat_pcts: timeline_pct_marks(total_ticks, ticks_per_beat),
      bar_pcts: timeline_pct_marks(total_ticks, ticks_per_bar)
    }
  end

  defp timeline_pct_marks(total_ticks, step) do
    0..total_ticks//step
    |> Enum.map(fn tick -> Float.round(tick / total_ticks * 100, 3) end)
  end

  defp chart_grid_xs(total_ticks, step, width) do
    0..total_ticks//step
    |> Enum.map(fn tick -> Float.round(tick / total_ticks * width, 2) end)
  end

  # Groups a rendered `music` timeline's frames by note (`{channel,
  # note}`), one polyline per note, for an SVG line chart of `value_key`
  # (`:pressure`, `:bend`, or `:slide`) over time.
  defp build_chart(
         music,
         value_key,
         {min_v, max_v},
         render_scope,
         %SongContext{} = song_context,
         projection
       ) do
    colors = note_color_map(music, render_scope)

    music
    |> Enum.flat_map(fn frame ->
      local_tick = SongContext.ms_to_ticks(song_context, frame.at_ms)
      global_tick = project_tick(local_tick, projection)
      x = global_tick / projection.total_ticks * 600

      Enum.map(frame.notes, &{{&1.channel, &1.note}, x, Map.fetch!(&1, value_key)})
    end)
    |> Enum.group_by(
      fn {id, _x, _value} -> id end,
      fn {_id, x, value} -> {x, value} end
    )
    |> Enum.map(fn {{channel, note}, points} ->
      %{
        channel: channel,
        note: note,
        color: Map.fetch!(colors, {channel, note}),
        points: chart_points(points, min_v, max_v)
      }
    end)
    |> Enum.sort_by(& &1.channel)
  end

  # A piano-roll style matrix: one row per semitone between the lowest
  # and highest sounding note (highest pitch on top), so vertical
  # spacing matches real chromatic distance. A row may contain multiple
  # bars (same pitch reused later by another chord/channel).
  defp build_note_matrix(music, render_scope, %SongContext{} = song_context, projection) do
    colors = note_color_map(music, render_scope)

    segments =
      music
      |> Enum.flat_map(fn frame -> Enum.map(frame.notes, &{&1, frame.at_ms}) end)
      |> Enum.group_by(fn {note, _at_ms} -> {note.note, note.channel} end)
      |> Enum.flat_map(fn {{note_number, channel}, entries} ->
        {sample, _at_ms} = hd(entries)
        start_entry = Enum.find(entries, fn {note, _} -> note.note_on end)
        end_entry = Enum.find(entries, fn {note, _} -> note.note_off end)

        if start_entry && end_entry do
          start_ms = elem(start_entry, 1)
          end_ms = elem(end_entry, 1)

          start_tick =
            song_context |> SongContext.ms_to_ticks(start_ms) |> project_tick(projection)

          end_tick = song_context |> SongContext.ms_to_ticks(end_ms) |> project_tick(projection)
          left_pct = start_tick / projection.total_ticks * 100
          width_pct = max((end_tick - start_tick) / projection.total_ticks * 100, 0.5)

          style =
            "left: #{Float.round(left_pct * 1.0, 2)}%; " <>
              "width: #{Float.round(width_pct * 1.0, 2)}%; " <>
              "background-color: #{Map.fetch!(colors, {channel, note_number})};"

          [
            %{
              note: note_number,
              label: "#{sample.note_name}#{sample.octave}",
              style: style
            }
          ]
        else
          []
        end
      end)

    case segments do
      [] ->
        []

      _ ->
        rows_by_note =
          segments
          |> Enum.group_by(& &1.note)

        {min_note, max_note} = rows_by_note |> Map.keys() |> Enum.min_max()

        for note_number <- max_note..min_note//-1 do
          case Map.get(rows_by_note, note_number) do
            nil ->
              {note_name, octave} = Render.note_name(note_number)
              %{note: note_number, label: "#{note_name}#{octave}", styles: []}

            note_segments ->
              label = note_segments |> hd() |> Map.fetch!(:label)
              styles = note_segments |> Enum.map(& &1.style)
              %{note: note_number, label: label, styles: styles}
          end
        end
    end
  end

  # Assigns each distinct `{channel, note}` a stable color (ordered by
  # channel) shared by both the line charts and the note matrix, so the
  # same note always reads as the same color across visualizations.
  defp note_color_map(music, {:entry, entry_index}) when is_integer(entry_index) do
    base_color = timeline_color(entry_index)
    events = music |> distinct_note_events() |> sort_voice_events()
    total = length(events)

    events
    |> Enum.with_index()
    |> Map.new(fn {%{channel: channel, note: note}, index} ->
      {{channel, note}, color_with_alpha(base_color, voice_alpha(index, total))}
    end)
  end

  defp note_color_map(music, :full_song) do
    music
    |> distinct_note_events()
    |> Enum.group_by(&Map.get(&1, :song_entry_index, 0))
    |> Enum.flat_map(fn {entry_index, events} ->
      base_color = timeline_color(entry_index)

      events
      |> sort_voice_events()
      |> then(fn sorted_events -> {sorted_events, length(sorted_events)} end)
      |> then(fn {sorted_events, total} ->
        sorted_events
        |> Enum.with_index()
        |> Enum.map(fn {%{channel: channel, note: note}, index} ->
          {{channel, note}, color_with_alpha(base_color, voice_alpha(index, total))}
        end)
      end)
    end)
    |> Map.new()
  end

  defp note_color_map(music, _render_scope) do
    music
    |> Enum.flat_map(& &1.notes)
    |> Enum.uniq_by(&{&1.channel, &1.note})
    |> Enum.sort_by(& &1.channel)
    |> Enum.with_index()
    |> Map.new(fn {%{channel: channel, note: note}, index} ->
      {{channel, note}, Enum.at(@chart_colors, rem(index, length(@chart_colors)))}
    end)
  end

  defp distinct_note_events(music) do
    music
    |> Enum.flat_map(& &1.notes)
    |> Enum.uniq_by(&{&1.channel, &1.note})
  end

  defp sort_voice_events(events) do
    Enum.sort_by(events, fn event ->
      {Map.get(event, :event_index, 999), event.note, event.channel}
    end)
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

  defp detail_projection_model(
         song_entries,
         %SongContext{} = song_context,
         render_scope,
         duration_ms
       ) do
    entry_windows =
      Enum.map(song_entries, fn %{timeline_context: timeline_context} ->
        start_tick = SongContext.position_to_tick(song_context, timeline_context.start_beat)
        end_tick = start_tick + timeline_context.duration_ticks
        %{start_tick: start_tick, end_tick: end_tick}
      end)

    ticks_per_bar = SongContext.ticks_per_bar(song_context)

    total_ticks =
      case entry_windows do
        [] -> ticks_per_bar * 2
        _ -> entry_windows |> Enum.map(& &1.end_tick) |> Enum.max()
      end

    total_ticks = max(total_ticks, 1)
    local_total_ticks = max(SongContext.ms_to_ticks(song_context, duration_ms), 1)

    {target_start_tick, target_end_tick} =
      case render_scope do
        {:entry, index} when is_integer(index) ->
          case Enum.at(entry_windows, index) do
            %{start_tick: start_tick, end_tick: end_tick} -> {start_tick, end_tick}
            _ -> {0, total_ticks}
          end

        _ ->
          {0, total_ticks}
      end

    %{
      total_ticks: total_ticks,
      local_total_ticks: local_total_ticks,
      target_start_tick: target_start_tick,
      target_end_tick: target_end_tick
    }
  end

  defp project_tick(local_tick, projection) do
    span = max(projection.target_end_tick - projection.target_start_tick, 1)
    ratio = local_tick / projection.local_total_ticks
    mapped_tick = projection.target_start_tick + ratio * span
    mapped_tick |> max(projection.target_start_tick) |> min(projection.target_end_tick)
  end

  defp detail_playhead_x(nil, _projection, _width), do: nil

  defp detail_playhead_x(playhead_pct, projection, width) when is_number(playhead_pct) do
    local_tick = projection.local_total_ticks * (playhead_pct / 100)
    global_tick = project_tick(local_tick, projection)
    Float.round(global_tick / projection.total_ticks * width, 2)
  end

  defp detail_playhead_x(_playhead_pct, _projection, _width), do: nil

  defp detail_playhead_pct(nil, _projection), do: nil

  defp detail_playhead_pct(playhead_pct, projection) when is_number(playhead_pct) do
    local_tick = projection.local_total_ticks * (playhead_pct / 100)
    global_tick = project_tick(local_tick, projection)
    Float.round(global_tick / projection.total_ticks * 100, 3)
  end

  defp detail_playhead_pct(_playhead_pct, _projection), do: nil

  # Bend's absolute range is tiny (see `Mensch.NoteShape`'s
  # `@vibrato_depth`), so it gets its own dynamic min/max instead of
  # being squashed flat against a fixed +/-1.0 scale.
  defp value_range(music) do
    values = for frame <- music, note <- frame.notes, do: note.bend

    case Enum.min_max(values) do
      {same, same} -> {same - 0.0001, same + 0.0001}
      {min_v, max_v} -> {min_v, max_v}
    end
  end
end
