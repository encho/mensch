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

  @refresh_interval_ms 100
  @chart_colors ["#FF9F1A", "#C96A00", "#2D8C82", "#4E6E8E", "#B3862C", "#8C5A2B"]

  @impl true
  def mount(_params, _session, socket) do
    samples = SampleDb.default_samples()
    active_sample_index = 0
    active_sample = Enum.at(samples, active_sample_index, %{})
    sample_entries = Map.get(active_sample, :sample_entries, [])

    sample_context =
      Map.get(active_sample, :sample_context, SampleDb.default_sample_context())

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:render_data, nil)
      |> assign(:player_status, Player.status())
      |> assign(:play_started_at, nil)
      |> assign(:playhead_pct, nil)
      |> assign(:samples, samples)
      |> assign(:active_sample_index, active_sample_index)
      |> assign(:sample_entries, sample_entries)
      |> assign(:sample_context, sample_context)
      |> assign(:view_modal_open, false)
      |> assign(:view_title, nil)
      |> assign(:render_scope, :full_sample)
      |> assign(:loop_full_sample, false)
      |> assign(:manual_stop, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("view_full_sample", _params, socket) do
    render_data = full_sample_render_data(socket)

    {:noreply,
     socket
     |> assign(:render_data, render_data)
     |> assign(:view_title, "Full Sample")
     |> assign(:render_scope, :full_sample)
     |> assign(:view_modal_open, true)}
  end

  def handle_event("play_full_sample", _params, socket) do
    render_data = full_sample_render_data(socket)

    {:noreply,
     socket
     |> assign(:render_data, render_data)
     |> assign(:render_scope, :full_sample)
     |> assign(:manual_stop, false)
     |> start_playback(render_data)}
  end

  def handle_event("toggle_loop_full_sample", _params, socket) do
    {:noreply, update(socket, :loop_full_sample, &(!&1))}
  end

  def handle_event("activate_sample", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, ""} ->
        case Enum.at(socket.assigns.samples, index) do
          %{sample_entries: sample_entries, sample_context: sample_context} ->
            Player.stop()

            {:noreply,
             socket
             |> assign(:active_sample_index, index)
             |> assign(:sample_entries, sample_entries)
             |> assign(:sample_context, sample_context)
             |> assign(:render_data, nil)
             |> assign(:view_modal_open, false)
             |> assign(:view_title, nil)
             |> assign(:render_scope, :full_sample)
             |> assign(:player_status, Player.status())
             |> assign(:play_started_at, nil)
             |> assign(:playhead_pct, nil)
             |> assign(:manual_stop, true)}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("view_entry", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, ""} ->
        case Enum.at(socket.assigns.sample_entries, index) do
          %{chord_spec: %ChordSpec{} = chord_spec} ->
            render_data = entry_render_data(socket, index)

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
        case Enum.at(socket.assigns.sample_entries, index) do
          %{chord_spec: %ChordSpec{}} ->
            render_data = entry_render_data(socket, index)

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

      loop_full_sample?(socket) ->
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
          detail_total_ticks =
            max(SampleContext.ms_to_ticks(assigns.sample_context, duration_ms), 1)

          assigns
          |> assign(
            :pressure_chart,
            build_chart(
              music,
              :pressure,
              {0, 127},
              assigns.render_scope,
              assigns.sample_context,
              detail_total_ticks
            )
          )
          |> assign(
            :slide_chart,
            build_chart(
              music,
              :slide,
              {0, 127},
              assigns.render_scope,
              assigns.sample_context,
              detail_total_ticks
            )
          )
          |> assign(
            :bend_chart,
            build_chart(
              music,
              :bend,
              value_range(music),
              assigns.render_scope,
              assigns.sample_context,
              detail_total_ticks
            )
          )
          |> assign(:debug_rows, debug_rows(music))
          |> assign(
            :note_matrix,
            build_note_matrix(
              music,
              assigns.render_scope,
              assigns.sample_context,
              detail_total_ticks
            )
          )
          |> assign(:chart_grid, chart_grid_model(assigns.sample_context, detail_total_ticks))
          |> assign(
            :note_matrix_grid,
            note_matrix_grid_model(assigns.sample_context, detail_total_ticks)
          )
          |> assign(
            :detail_chart_playhead_x,
            detail_playhead_x(assigns.playhead_pct, 600)
          )
          |> assign(
            :detail_matrix_playhead_pct,
            detail_playhead_pct(assigns.playhead_pct)
          )
      end

    assigns =
      assign(
        assigns,
        :sample_timeline,
        sample_timeline_model(
          assigns.sample_entries,
          assigns.sample_context,
          assigns.playhead_pct,
          assigns.render_scope
        )
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status}>
      <div class="mx-auto max-w-6xl space-y-6">
        <div id="samples-section" class="space-y-3 border border-zinc-700/70 bg-zinc-950/85 p-4">
          <div class="text-[11px] uppercase tracking-wide text-zinc-400">Samples</div>

          <div class="overflow-x-auto border border-zinc-700/60">
            <table class="w-full min-w-[860px] text-left font-mono text-[11px]">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-2 py-1.5 font-normal">Name</th>
                  <th class="px-2 py-1.5 font-normal">Tempo</th>
                  <th class="px-2 py-1.5 font-normal">Time Sig</th>
                  <th class="px-2 py-1.5 font-normal">Chords</th>
                  <th class="px-2 py-1.5 font-normal">Duration</th>
                  <th class="px-2 py-1.5 font-normal text-right">Status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{sample, index} <- Enum.with_index(@samples)}
                  class={[
                    "text-zinc-200",
                    @active_sample_index == index && "bg-amber-500/10"
                  ]}
                >
                  <td class="px-2 py-1.5 text-zinc-100">{Map.get(sample, :name, "Unnamed")}</td>
                  <td class="px-2 py-1.5">{Map.get(sample.sample_context, :bpm, 0)} bpm</td>
                  <td class="px-2 py-1.5">
                    {elem(sample.sample_context.time_signature, 0)}/{elem(
                      sample.sample_context.time_signature,
                      1
                    )}
                  </td>
                  <td class="px-2 py-1.5">{length(Map.get(sample, :sample_entries, []))}</td>
                  <td class="px-2 py-1.5">
                    {sample_duration_label(
                      Map.get(sample, :sample_entries, []),
                      Map.get(sample, :sample_context, @sample_context)
                    )}
                  </td>
                  <td class="px-2 py-1.5 text-right">
                    <button
                      type="button"
                      id={"activate-sample-#{index}"}
                      phx-click="activate_sample"
                      phx-value-index={index}
                      class={[
                        "h-9 border px-3 text-[11px] uppercase tracking-wide transition-colors duration-150",
                        (@active_sample_index == index &&
                           "border-amber-500 text-amber-200 ring-1 ring-amber-500/50 bg-amber-500/10") ||
                          "border-zinc-600 text-zinc-300 hover:border-amber-400 hover:text-amber-200"
                      ]}
                    >
                      {if @active_sample_index == index, do: "Active", else: "Activate"}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div id="render-section" class="space-y-4 border border-zinc-700/70 bg-zinc-950/85 p-4">
          <div class="text-[11px] uppercase tracking-wide text-zinc-400">Active Sample Playback</div>

          <div class="font-mono text-[11px] text-zinc-200">
            Selected sample: {active_sample_name(@samples, @active_sample_index)}
          </div>

          <div class="font-mono text-[11px] text-zinc-300">
            Timing settings: {sample_context_label(@sample_context)}
          </div>

          <div class="font-mono text-[11px] text-zinc-400">
            Total playback length: {sample_duration_label(@sample_entries, @sample_context)}
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              id="toggle-loop-full-sample"
              phx-click="toggle_loop_full_sample"
              aria-pressed={@loop_full_sample}
              class={[
                "flex h-9 items-center border px-3 text-[11px] uppercase tracking-wide transition-colors duration-150",
                (@loop_full_sample &&
                   "border-amber-500 text-amber-200 ring-1 ring-amber-500/50 bg-amber-500/10") ||
                  "border-zinc-600 text-zinc-300 hover:border-amber-400 hover:text-amber-200"
              ]}
            >
              Loop {if(@loop_full_sample, do: "On", else: "Off")}
            </button>
            <button
              type="button"
              id="view-full-sample"
              phx-click="view_full_sample"
              class="flex h-9 items-center border border-zinc-600 px-3 text-[11px] uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
            >
              View
            </button>
            <button
              type="button"
              id="play-full-sample"
              aria-label="Play full sample"
              phx-click="play_full_sample"
              class="flex size-9 items-center justify-center border border-zinc-600 bg-transparent text-zinc-300 ring-1 ring-zinc-500/40 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200 hover:ring-amber-500/40"
            >
              <.icon name="hero-play-solid" class="size-4" />
            </button>
            <button
              type="button"
              id="stop-full-sample"
              aria-label="Stop full sample"
              phx-click="stop"
              class="flex size-9 items-center justify-center border border-zinc-600 bg-transparent text-zinc-300 ring-1 ring-zinc-500/40 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200 hover:ring-amber-500/40"
            >
              <.icon name="hero-stop-solid" class="size-4" />
            </button>
          </div>

          <div class="overflow-x-auto border border-zinc-700/60">
            <table class="w-full min-w-[860px] text-left font-mono text-[11px]">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-2 py-1.5 font-normal">ChordSpec</th>
                  <th class="px-2 py-1.5 font-normal">Machine</th>
                  <th class="px-2 py-1.5 font-normal">Start</th>
                  <th class="px-2 py-1.5 font-normal">Duration</th>
                  <th class="px-2 py-1.5 font-normal text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{entry, index} <- Enum.with_index(@sample_entries)} class="text-zinc-200">
                  <td class="px-2 py-1.5 text-zinc-100">
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
                    <div class="leading-tight text-zinc-100">
                      {start_label_primary(@sample_context, entry.timeline_context.start_beat)}
                    </div>
                    <div class="leading-tight text-zinc-500">
                      {start_label_secondary(@sample_context, entry.timeline_context.start_beat)}
                    </div>
                  </td>
                  <td class="px-2 py-1.5 align-top">
                    <div class="leading-tight text-zinc-100">
                      {duration_label_primary(@sample_context, entry.timeline_context.duration_ticks)}
                    </div>
                    <div class="leading-tight text-zinc-500">
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
                        class="flex h-9 items-center border border-zinc-600 px-3 text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
                      >
                        View
                      </button>
                      <button
                        type="button"
                        id={"play-entry-#{index}"}
                        aria-label={"Play #{chord_label(entry.chord_spec)}"}
                        phx-click="play_entry"
                        phx-value-index={index}
                        class="flex size-9 items-center justify-center border border-zinc-600 bg-transparent text-zinc-300 ring-1 ring-zinc-500/40 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200 hover:ring-amber-500/40"
                      >
                        <.icon name="hero-play-solid" class="size-4" />
                      </button>
                      <button
                        type="button"
                        id={"stop-entry-#{index}"}
                        aria-label={"Stop #{chord_label(entry.chord_spec)}"}
                        phx-click="stop"
                        class="flex size-9 items-center justify-center border border-zinc-600 bg-transparent text-zinc-300 ring-1 ring-zinc-500/40 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200 hover:ring-amber-500/40"
                      >
                        <.icon name="hero-stop-solid" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.sample_timeline model={@sample_timeline} />
        </div>
      </div>
      <div
        :if={@view_modal_open and @render_data}
        id="render-view-modal"
        class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-zinc-950/85 p-4"
      >
        <div class="w-full max-w-6xl space-y-4 border border-zinc-700/80 bg-zinc-950 p-4">
          <div class="flex items-center justify-between border-b border-zinc-700/70 pb-2">
            <div class="text-sm uppercase tracking-wide text-zinc-200">{@view_title || "View"}</div>
            <button
              type="button"
              id="close-view-modal"
              phx-click="close_view"
              class="border border-zinc-600 px-2 py-1 text-[11px] uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
            >
              Close
            </button>
          </div>

          <div class="font-mono text-[11px] text-zinc-400">
            {@render_data.bpm} bpm · {elem(@render_data.time_signature, 0)}/{elem(
              @render_data.time_signature,
              1
            )} · {@render_data.granularity_ms}ms ticks · {@render_data.duration_ms}ms · {length(
              @render_data.music
            )} frames
          </div>

          <div id="debug-frames" class="border border-zinc-700/60">
            <div class="border-b border-zinc-700/60 px-3 py-1.5 text-[11px] uppercase tracking-wide text-zinc-400">
              All frames
            </div>
            <div class="max-h-48 overflow-y-auto">
              <table class="w-full text-left font-mono text-[11px]">
                <thead class="sticky top-0 bg-zinc-950">
                  <tr class="border-b border-zinc-700/60 text-zinc-400">
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
                    class="border-b border-zinc-800/70 text-zinc-300 last:border-0"
                  >
                    <td class="px-3 py-1.5">{row.at_ms}</td>
                    <td class="px-3 py-1.5 text-zinc-100">{row.note_name}{row.octave}</td>
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

          <div id="note-matrix" class="border border-zinc-700/60">
            <div class="border-b border-zinc-700/60 px-3 py-1.5 text-[11px] uppercase tracking-wide text-zinc-400">
              Note matrix
            </div>
            <div class="relative py-2">
              <div
                :for={x <- @note_matrix_grid.subbeat_pcts}
                class="pointer-events-none absolute inset-y-0 z-0 w-px bg-zinc-700/30"
                style={"left: #{x}%;"}
              >
              </div>
              <div
                :for={x <- @note_matrix_grid.beat_pcts}
                class="pointer-events-none absolute inset-y-0 z-0 w-px bg-zinc-500/40"
                style={"left: #{x}%;"}
              >
              </div>
              <div
                :for={x <- @note_matrix_grid.bar_pcts}
                class="pointer-events-none absolute inset-y-0 z-0 w-px bg-amber-400/35"
                style={"left: #{x}%;"}
              >
              </div>
              <div
                :if={not is_nil(@detail_matrix_playhead_pct)}
                class="pointer-events-none absolute inset-y-0 z-20 w-px bg-amber-300/80"
                style={"left: #{@detail_matrix_playhead_pct}%;"}
              >
              </div>
              <div
                :for={{row, index} <- Enum.with_index(@note_matrix)}
                class={[
                  "relative z-10 flex h-2.5 items-center border-b border-zinc-700/60 last:border-0",
                  rem(index, 2) == 0 && "bg-zinc-900/70"
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
                  (Enum.empty?(row.styles) && "text-zinc-600") || "text-zinc-200"
                ]}>
                  {row.label}
                </span>
              </div>
            </div>
            <div class="flex justify-between px-3 pb-2 pt-1 font-mono text-[10px] text-zinc-500">
              <span>{local_timeline_start_label()}</span>
              <span>{local_timeline_end_label(@sample_context, @render_data.duration_ms)}</span>
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
                "flex size-14 items-center justify-center border border-zinc-600 bg-transparent transition-colors duration-150",
                (playing?(@player_status) && "text-zinc-700 ring-1 ring-zinc-700/60") ||
                  "text-zinc-300 ring-1 ring-zinc-500/40 hover:border-amber-400 hover:text-amber-200 hover:ring-amber-500/40",
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
                "flex size-14 items-center justify-center border border-zinc-600 bg-transparent transition-colors duration-150",
                (playing?(@player_status) &&
                   "text-zinc-300 ring-1 ring-zinc-500/40 hover:border-amber-400 hover:text-amber-200 hover:ring-amber-500/40") ||
                  "text-zinc-700 ring-1 ring-zinc-700/60",
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

  defp sample_timeline(assigns) do
    ~H"""
    <div id="sample-timeline" class="space-y-2 border border-zinc-700/60 bg-zinc-950/70 p-3">
      <div class="flex items-center justify-between font-mono text-[11px] text-zinc-400">
        <span class="uppercase tracking-wide">Timeline</span>
        <span>
          {@model.row_count} rows · {@model.bar_count} bars · {@model.beat_count} beats · {@model.total_ticks} ticks
        </span>
      </div>

      <svg
        viewBox={"0 0 #{@model.svg_width} #{@model.svg_height}"}
        class="w-full border border-zinc-700/60 bg-zinc-950/80"
      >
        <line
          :for={x <- @model.subbeat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="#5B6472"
          stroke-opacity="0.3"
          stroke-width="1"
        />
        <line
          :for={x <- @model.beat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="#7A8596"
          stroke-opacity="0.35"
          stroke-width="1"
        />
        <line
          :for={{x, bar_number} <- @model.bar_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={@model.svg_height}
          stroke="#FFB55A"
          stroke-opacity="0.4"
          stroke-width="1.2"
        />

        <rect
          :for={lane <- @model.lanes}
          x="0"
          y={lane.y}
          width={@model.svg_width}
          height={lane.height}
          fill="#1A202B"
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
          fill="#D1D8E2"
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
          fill="#FFCA87"
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
          stroke="#FFC16B"
          stroke-opacity="0.9"
          stroke-width="1.5"
        />
      </svg>

      <div class="flex items-center justify-between font-mono text-[10px] text-zinc-500">
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
      <div class="mb-1 text-[11px] uppercase tracking-wide text-zinc-400">{@title}</div>
      <svg viewBox="0 0 600 120" class="w-full border border-zinc-700/60 bg-zinc-950">
        <line
          :for={x <- @grid.subbeat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2="120"
          stroke="#5B6472"
          stroke-opacity="0.32"
          stroke-width="1"
        />
        <line
          :for={x <- @grid.beat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2="120"
          stroke="#7A8596"
          stroke-opacity="0.38"
          stroke-width="1"
        />
        <line
          :for={x <- @grid.bar_xs}
          x1={x}
          y1="0"
          x2={x}
          y2="120"
          stroke="#FFB55A"
          stroke-opacity="0.45"
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
          stroke="#FFC16B"
          stroke-opacity="0.9"
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

  defp loop_full_sample?(socket) do
    socket.assigns.loop_full_sample and
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

  defp active_sample_name(samples, active_sample_index)
       when is_list(samples) and is_integer(active_sample_index) do
    samples
    |> Enum.at(active_sample_index, %{})
    |> Map.get(:name, "Unnamed")
  end

  defp sample_context_label(%SampleContext{} = sample_context) do
    {num, den} = sample_context.time_signature
    "#{sample_context.bpm} bpm · #{num}/#{den} · ppq #{sample_context.ppq}"
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

  defp start_label_primary(%SampleContext{} = sample_context, %BeatPosition{} = start_beat) do
    tick = SampleContext.position_to_tick(sample_context, start_beat)
    ms = SampleContext.ticks_to_ms(sample_context, tick)

    "bar #{start_beat.bar} · beat #{start_beat.beat} · #{SampleContext.format_timestamp(ms)}"
  end

  defp start_label_secondary(%SampleContext{} = sample_context, %BeatPosition{} = start_beat) do
    tick = SampleContext.position_to_tick(sample_context, start_beat)
    "tick #{tick}"
  end

  defp duration_label_primary(%SampleContext{} = sample_context, duration_ticks) do
    ticks_per_bar = SampleContext.ticks_per_bar(sample_context)
    ticks_per_beat = SampleContext.ticks_per_beat(sample_context)
    duration_ms = SampleContext.ticks_to_ms(sample_context, duration_ticks)
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
    max_end_tick =
      case sample_entries do
        [] ->
          0

        _ ->
          sample_entries
          |> Enum.map(fn %{timeline_context: timeline_context} ->
            start_tick =
              SampleContext.position_to_tick(sample_context, timeline_context.start_beat)

            start_tick + timeline_context.duration_ticks
          end)
          |> Enum.max()
      end

    SampleContext.ticks_to_ms(sample_context, max_end_tick)
  end

  defp full_sample_render_data(socket) do
    PerformanceAssembler.generate_sample(
      socket.assigns.sample_entries,
      socket.assigns.sample_context
    )
  end

  defp entry_render_data(socket, entry_index) when is_integer(entry_index) do
    case Enum.at(socket.assigns.sample_entries, entry_index) do
      %{timeline_context: %TimelineContext{} = timeline_context} ->
        sample_context = socket.assigns.sample_context
        sample_render_data = full_sample_render_data(socket)

        start_tick = SampleContext.position_to_tick(sample_context, timeline_context.start_beat)
        end_tick = start_tick + timeline_context.duration_ticks

        scoped_music =
          sample_render_data.music
          |> Enum.map(fn frame ->
            notes =
              Enum.filter(frame.notes, fn note ->
                Map.get(note, :sample_entry_index) == entry_index
              end)

            {frame, notes}
          end)
          |> Enum.filter(fn {frame, notes} ->
            frame.at_tick >= start_tick and frame.at_tick <= end_tick and notes != []
          end)
          |> Enum.map(fn {frame, notes} ->
            local_tick = frame.at_tick - start_tick

            %{
              at_tick: local_tick,
              at_ms: SampleContext.ticks_to_ms(sample_context, local_tick),
              notes: notes
            }
          end)

        %{
          sample_render_data
          | duration_ms:
              SampleContext.ticks_to_ms(sample_context, timeline_context.duration_ticks),
            music: scoped_music
        }

      _ ->
        nil
    end
  end

  defp local_timeline_start_label do
    "bar 0 · beat 0 · 0ms"
  end

  defp local_timeline_end_label(%SampleContext{} = sample_context, duration_ms) do
    total_ticks = SampleContext.ms_to_ticks(sample_context, duration_ms)
    ticks_per_bar = SampleContext.ticks_per_bar(sample_context)
    ticks_per_beat = SampleContext.ticks_per_beat(sample_context)

    bar = div(total_ticks, ticks_per_bar)
    bar_remainder = rem(total_ticks, ticks_per_bar)
    beat = div(bar_remainder, ticks_per_beat)
    tick_remainder = rem(bar_remainder, ticks_per_beat)

    musical_label =
      if tick_remainder == 0 do
        "bar #{bar} · beat #{beat}"
      else
        "bar #{bar} · beat #{beat} + #{tick_remainder}t"
      end

    "#{musical_label} · #{duration_ms}ms"
  end

  defp sample_timeline_model(
         sample_entries,
         %SampleContext{} = sample_context,
         playhead_pct,
         render_scope
       ) do
    svg_width = 1000
    lane_height = 22
    lane_gap = 8
    lanes_top = 22
    lanes_bottom = 12

    ticks_per_bar = SampleContext.ticks_per_bar(sample_context)
    ticks_per_beat = SampleContext.ticks_per_beat(sample_context)
    ticks_per_subbeat = max(div(ticks_per_beat, 4), 1)

    entries =
      Enum.map(sample_entries, fn %{chord_spec: chord_spec, timeline_context: timeline_context} ->
        start_tick = SampleContext.position_to_tick(sample_context, timeline_context.start_beat)
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
    beat_count = bar_count * SampleContext.beats_per_bar(sample_context)
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

  defp timeline_playhead_x(playhead_pct, :full_sample, _entries, total_ticks)
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

  defp chart_grid_model(%SampleContext{} = sample_context, total_ticks) do
    width = 600
    ticks_per_bar = SampleContext.ticks_per_bar(sample_context)
    ticks_per_beat = SampleContext.ticks_per_beat(sample_context)
    ticks_per_subbeat = max(div(ticks_per_beat, 4), 1)
    total_ticks = max(total_ticks, 1)

    %{
      subbeat_xs: chart_grid_xs(total_ticks, ticks_per_subbeat, width),
      beat_xs: chart_grid_xs(total_ticks, ticks_per_beat, width),
      bar_xs: chart_grid_xs(total_ticks, ticks_per_bar, width)
    }
  end

  defp note_matrix_grid_model(%SampleContext{} = sample_context, total_ticks) do
    ticks_per_bar = SampleContext.ticks_per_bar(sample_context)
    ticks_per_beat = SampleContext.ticks_per_beat(sample_context)
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
         %SampleContext{} = sample_context,
         total_ticks
       ) do
    colors = note_color_map(music, render_scope)
    total_ticks = max(total_ticks, 1)

    music
    |> Enum.flat_map(fn frame ->
      local_tick = SampleContext.ms_to_ticks(sample_context, frame.at_ms)
      x = local_tick / total_ticks * 600

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
  defp build_note_matrix(music, render_scope, %SampleContext{} = sample_context, total_ticks) do
    colors = note_color_map(music, render_scope)
    total_ticks = max(total_ticks, 1)

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

          start_tick = SampleContext.ms_to_ticks(sample_context, start_ms)
          end_tick = SampleContext.ms_to_ticks(sample_context, end_ms)
          left_pct = start_tick / total_ticks * 100
          width_pct = max((end_tick - start_tick) / total_ticks * 100, 0.5)

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
              {note_name, octave} = PerformanceAssembler.note_name(note_number)
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

  defp note_color_map(music, :full_sample) do
    music
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

  defp detail_playhead_x(nil, _width), do: nil

  defp detail_playhead_x(playhead_pct, width) when is_number(playhead_pct) do
    Float.round(playhead_pct / 100 * width, 2)
  end

  defp detail_playhead_x(_playhead_pct, _width), do: nil

  defp detail_playhead_pct(nil), do: nil

  defp detail_playhead_pct(playhead_pct) when is_number(playhead_pct) do
    Float.round(playhead_pct * 1.0, 3)
  end

  defp detail_playhead_pct(_playhead_pct), do: nil

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
