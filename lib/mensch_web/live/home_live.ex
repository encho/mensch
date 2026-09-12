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

  @refresh_interval_ms 33
  @chart_colors ["#FF9F1A", "#C96A00", "#2D8C82", "#4E6E8E", "#B3862C", "#8C5A2B"]
  @inactive_note_color "rgba(122, 133, 150, 0.32)"

  @impl true
  def mount(_params, _session, socket) do
    samples = SampleDb.default_samples()
    active_sample_index = 0
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
      |> assign(:active_sample_index, active_sample_index)
      |> assign(:sample_entries, sample_entries)
      |> assign(:sample_context, sample_context)
      |> assign(
        :sample_timeline_static,
        sample_timeline_static_model(sample_entries, sample_context)
      )
      |> assign(:render_scope, :full_sample)
      |> assign(:loop_full_sample, false)
      |> assign(:show_detail_panel, false)
      |> assign(:selected_note_key, nil)
      |> assign(:manual_stop, false)
      |> assign_detail_content()

    {:ok, socket}
  end

  @impl true
  def handle_event("play_full_sample", _params, socket) do
    render_data =
      PerformanceAssembler.generate_sample(
        socket.assigns.sample_entries,
        socket.assigns.sample_context
      )

    {:noreply,
     socket
     |> assign(:render_data, render_data)
     |> assign(:render_scope, :full_sample)
     |> assign(:selected_note_key, nil)
     |> assign_detail_content()
     |> assign(:manual_stop, false)
     |> start_playback(render_data)}
  end

  def handle_event("toggle_loop_full_sample", _params, socket) do
    {:noreply, update(socket, :loop_full_sample, &(!&1))}
  end

  def handle_event("toggle_detail_panel", _params, socket) do
    {:noreply, update(socket, :show_detail_panel, &(!&1))}
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
             |> assign(:sample_context, sample_context)
             |> assign(
               :sample_timeline_static,
               sample_timeline_static_model(sample_entries, sample_context)
             )
             |> assign(:render_data, render_data)
             |> assign(:render_scope, :full_sample)
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
          {:noreply,
           socket |> assign(:manual_stop, false) |> start_playback(socket.assigns.render_data)}

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
          {:noreply,
           socket |> assign(:manual_stop, false) |> start_playback(socket.assigns.render_data)}

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
          assigns.playhead_pct
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
                  <th class="px-2 py-1.5 font-normal">Voicing</th>
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
                  <td class="px-2 py-1.5 text-zinc-300">
                    {sample_voicing_strategies_label(Map.get(sample, :sample_entries, []))}
                  </td>
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

          <div class="font-mono text-[11px] text-zinc-300">
            Voicing strategies: {sample_voicing_strategies_label(@sample_entries)}
          </div>

          <div class="font-mono text-[11px] text-zinc-400">
            Total playback length: {sample_duration_label(@sample_entries, @sample_context)}
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              id="toggle-detail-panel"
              phx-click="toggle_detail_panel"
              aria-pressed={@show_detail_panel}
              class={[
                "flex h-9 items-center border px-3 text-[11px] uppercase tracking-wide transition-colors duration-150",
                (@show_detail_panel &&
                   "border-amber-500 text-amber-200 ring-1 ring-amber-500/50 bg-amber-500/10") ||
                  "border-zinc-600 text-zinc-300 hover:border-amber-400 hover:text-amber-200"
              ]}
            >
              {if @show_detail_panel, do: "Hide Detail Charts", else: "Show Detail Charts"}
            </button>
            <.link
              id="download-mpe-midi"
              href={~p"/exports/sample/#{@active_sample_index}/mpe.mid"}
              class="flex h-9 items-center border border-zinc-600 px-3 text-[11px] uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
            >
              Download MPE MIDI
            </.link>
            <.link
              id="download-bitwig-mpe-midi"
              href={~p"/exports/sample/#{@active_sample_index}/bitwig-mpe.mid"}
              class="flex h-9 items-center border border-zinc-600 px-3 text-[11px] uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
            >
              Download Bitwig MPE MIDI
            </.link>
            <.link
              id="download-mpe-report"
              href={~p"/exports/sample/#{@active_sample_index}/mpe-events.txt"}
              class="flex h-9 items-center border border-zinc-600 px-3 text-[11px] uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
            >
              Export Event Report
            </.link>
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
            <button
              type="button"
              id="panic-all-notes"
              phx-click="panic_all_notes"
              class="flex h-9 items-center border border-red-500/60 bg-red-500/10 px-3 text-[11px] uppercase tracking-wide text-red-200 transition-colors duration-150 hover:border-red-400 hover:bg-red-500/20"
            >
              Panic All Notes
            </button>
          </div>

          <div class="overflow-x-auto border border-zinc-700/60">
            <table class="w-full min-w-[980px] text-left font-mono text-[11px]">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-2 py-1.5 font-normal">ChordSpec</th>
                  <th class="px-2 py-1.5 font-normal">Machine</th>
                  <th class="px-2 py-1.5 font-normal">Voicing</th>
                  <th class="px-2 py-1.5 font-normal">Start</th>
                  <th class="px-2 py-1.5 font-normal">Duration</th>
                  <th class="px-2 py-1.5 font-normal text-right">Status</th>
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
                  <td class="px-2 py-1.5">{machine_label(entry.machine)}</td>
                  <td class="px-2 py-1.5 text-zinc-300">{voicing_strategy_label(entry.machine)}</td>
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
                      {duration_label_primary(@sample_context, entry.timeline_context)}
                    </div>
                    <div class="leading-tight text-zinc-500">
                      {duration_label_secondary(@sample_context, entry.timeline_context)}
                    </div>
                  </td>
                  <td class="px-2 py-1.5 text-right text-zinc-500">Ready</td>
                </tr>
              </tbody>
            </table>
          </div>

          <.sample_timeline model={@sample_timeline} />
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
          />
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
          {@model.row_count} rows · {@model.bar_count} bars · {@model.beat_count} beats · {@model.total_mbeats} mbeats
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
    done_after_ms = playing_duration_ms + Map.get(render_data, :granularity_ms, 0)
    Process.send_after(self(), {:playback_done, playback_ref}, done_after_ms)
    play_started_at = System.monotonic_time(:millisecond)

    socket
    |> assign(:player_status, Player.status())
    |> assign(:play_started_at, play_started_at)
    |> assign(:playing_duration_ms, playing_duration_ms)
    |> assign(:playback_ref, playback_ref)
    |> assign(:playhead_pct, playhead_pct(:playing, play_started_at, playing_duration_ms))
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
  defp debug_rows(frames) do
    Enum.flat_map(frames, fn frame ->
      Enum.map(frame.notes, &Map.put(&1, :at_ms, frame.at_ms))
    end)
  end

  defp active_sample_name(samples, active_sample_index)
       when is_list(samples) and is_integer(active_sample_index) do
    samples
    |> Enum.at(active_sample_index, %{})
    |> Map.get(:name, "Unnamed")
  end

  defp sample_context_label(%SampleContext{} = sample_context) do
    {num, den} = sample_context.time_signature
    "#{sample_context.bpm} bpm · #{num}/#{den} · frame #{sample_context.frame_mbeats} mbeats"
  end

  defp chord_label(%ChordSpec{} = chord_spec) do
    root = chord_spec.root |> Atom.to_string() |> String.replace("_sharp", "#") |> String.upcase()
    modifier = chord_spec.modifier |> Atom.to_string()
    "#{root} #{modifier} · Oct #{chord_spec.octave} · Inv #{chord_spec.inversion}"
  end

  defp machine_label(machine) do
    machine
    |> Mensch.Machine.id()
    |> Atom.to_string()
  end

  defp sample_voicing_strategies_label(sample_entries) when is_list(sample_entries) do
    labels =
      sample_entries
      |> Enum.map(&voicing_strategy_label(&1.machine))
      |> Enum.reject(&(&1 in ["-", ""]))
      |> Enum.uniq()

    case labels do
      [] -> "-"
      _ -> Enum.join(labels, ", ")
    end
  end

  defp voicing_strategy_label(%Mensch.Machines.SimpleChord{params: params}) do
    case Map.get(params, :voicing_strategy) do
      %{__struct__: module} when is_atom(module) ->
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      _ ->
        "-"
    end
  end

  defp voicing_strategy_label(_machine), do: "-"

  defp start_label_primary(%SampleContext{} = sample_context, %BeatPosition{} = start_beat) do
    mbeat = SampleContext.position_to_mbeat(sample_context, start_beat)
    ms = SampleContext.mbeats_to_ms(sample_context, mbeat)

    "bar #{start_beat.bar} · beat #{start_beat.beat} · #{SampleContext.format_timestamp(ms)}"
  end

  defp start_label_secondary(%SampleContext{} = sample_context, %BeatPosition{} = start_beat) do
    mbeat = SampleContext.position_to_mbeat(sample_context, start_beat)
    "mbeat #{mbeat}"
  end

  defp duration_label_primary(
         %SampleContext{} = sample_context,
         %TimelineContext{} = timeline_context
       ) do
    duration_mbeats = TimelineContext.duration_mbeats(timeline_context)
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    duration_ms = SampleContext.mbeats_to_ms(sample_context, duration_mbeats)
    duration_s = duration_ms / 1000

    musical =
      cond do
        rem(duration_mbeats, mbeats_per_bar) == 0 ->
          bars = div(duration_mbeats, mbeats_per_bar)
          "#{bars} bar"

        rem(duration_mbeats, mbeats_per_beat) == 0 ->
          beats = div(duration_mbeats, mbeats_per_beat)
          "#{beats} beats"

        true ->
          beats = div(duration_mbeats, mbeats_per_beat)
          remainder_mbeats = rem(duration_mbeats, mbeats_per_beat)
          "#{beats} beats + #{remainder_mbeats} mbeats"
      end

    "#{musical} · #{:erlang.float_to_binary(duration_s, decimals: 2)}s"
  end

  defp duration_label_secondary(
         %SampleContext{} = _sample_context,
         %TimelineContext{} = timeline_context
       ) do
    duration_mbeats = TimelineContext.duration_mbeats(timeline_context)
    "#{duration_mbeats} mbeats"
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
      Enum.map(sample_entries, fn %{chord_spec: chord_spec, timeline_context: timeline_context} ->
        start_mbeat = SampleContext.position_to_mbeat(sample_context, timeline_context.start_beat)
        end_mbeat = start_mbeat + TimelineContext.duration_mbeats(timeline_context)

        %{label: short_chord_label(chord_spec), start_mbeat: start_mbeat, end_mbeat: end_mbeat}
      end)

    max_end_mbeat =
      case entries do
        [] -> mbeats_per_bar * 2
        _ -> entries |> Enum.map(& &1.end_mbeat) |> Enum.max()
      end

    bar_count = max(div(max_end_mbeat + mbeats_per_bar - 1, mbeats_per_bar), 2)
    total_mbeats = bar_count * mbeats_per_bar
    beat_count = bar_count * SampleContext.beats_per_bar(sample_context)
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
      |> Enum.map(fn {%{label: label, start_mbeat: start_mbeat, end_mbeat: end_mbeat}, index} ->
        lane_y = lanes_top + index * (lane_height + lane_gap)
        x = mbeat_to_svg_x(start_mbeat, total_mbeats)
        width = max(mbeat_to_svg_x(end_mbeat, total_mbeats) - x, 8)

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

  defp sample_timeline_with_playhead(nil, _render_scope, _playhead_pct), do: nil

  defp sample_timeline_with_playhead(
         %{
           source_entries: source_entries,
           total_mbeats: total_mbeats
         } = model,
         render_scope,
         playhead_pct
       ) do
    playhead_x = timeline_playhead_x(playhead_pct, render_scope, source_entries, total_mbeats)
    Map.put(model, :playhead_x, playhead_x)
  end

  defp timeline_playhead_x(nil, _render_scope, _entries, _total_mbeats), do: nil

  defp timeline_playhead_x(playhead_pct, :full_sample, _entries, total_mbeats)
       when is_number(playhead_pct) do
    mbeat_to_svg_x(total_mbeats * (playhead_pct / 100), total_mbeats)
  end

  defp timeline_playhead_x(playhead_pct, {:entry, index}, entries, total_mbeats)
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

  defp timeline_playhead_x(_playhead_pct, _render_scope, _entries, _total_mbeats), do: nil

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
  # note}`), one polyline per note, for an SVG line chart of `value_key`
  # (`:pressure`, `:bend`, or `:slide`) over time.
  defp build_chart(
         frames,
         value_key,
         {min_v, max_v},
         render_scope,
         selected_note_key,
         %SampleContext{} = _sample_context,
         total_mbeats
       ) do
    colors = note_color_map(frames, render_scope, selected_note_key)
    total_mbeats = max(total_mbeats, 1)

    frames
    |> Enum.flat_map(fn frame ->
      local_mbeat = frame.at_mbeat
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
      {channel, note} = series_channel_note(series_key)

      %{
        series_key: series_key,
        channel: channel,
        note: note,
        color: Map.fetch!(colors, series_key),
        points: chart_points(points, min_v, max_v)
      }
    end)
    |> Enum.sort_by(&chart_series_sort_key(&1, selected_note_key))
  end

  defp chart_series_sort_key(series, selected_note_key) do
    is_selected =
      not is_nil(selected_note_key) and {series.channel, series.note} == selected_note_key

    {is_selected, series.channel, series.note}
  end

  # A piano-roll style matrix: one row per semitone between the lowest
  # and highest sounding note (highest pitch on top), so vertical
  # spacing matches real chromatic distance. A row may contain multiple
  # bars (same pitch reused later by another chord/channel).
  defp build_note_matrix(
         frames,
         render_scope,
         selected_note_key,
         %SampleContext{} = _sample_context,
         total_mbeats
       ) do
    colors = note_color_map(frames, render_scope, selected_note_key)
    total_mbeats = max(total_mbeats, 1)

    segments =
      frames
      |> Enum.flat_map(fn frame -> Enum.map(frame.notes, &{&1, frame.at_mbeat}) end)
      |> Enum.group_by(fn {note, _at_mbeat} -> note_series_key(note) end)
      |> Enum.flat_map(fn {series_key, entries} ->
        {channel, note_number} = series_channel_note(series_key)

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
            note: note_number,
            label: label,
            active: note_selected?({channel, note_number}, selected_note_key),
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
          |> Enum.group_by(& &1.note)

        {min_note, max_note} = rows_by_note |> Map.keys() |> Enum.min_max()

        for note_number <- max_note..min_note//-1 do
          case Map.get(rows_by_note, note_number) do
            nil ->
              {note_name, octave} = PerformanceAssembler.note_name(note_number)

              %{
                note: note_number,
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
                    note: segment.note,
                    active: segment.active
                  }
                end)

              %{
                note: note_number,
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
  defp note_color_map(frames, render_scope, selected_note_key) do
    frames
    |> base_note_color_map(render_scope)
    |> Map.new(fn {note_key, color} ->
      {note_key, focus_color(note_key, color, selected_note_key)}
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
      {Map.get(event, :sample_entry_index, -1), Map.get(event, :event_index, 999), event.note,
       event.channel}
    end)
    |> Enum.with_index()
    |> Map.new(fn {event, index} ->
      {note_series_key(event), Enum.at(@chart_colors, rem(index, length(@chart_colors)))}
    end)
  end

  defp note_selected?(_note_key, nil), do: true
  defp note_selected?(note_key, selected_note_key), do: note_key == selected_note_key

  defp focus_color(_series_key, color, nil), do: color

  defp focus_color(series_key, color, {selected_channel, selected_note}) do
    {channel, note} = series_channel_note(series_key)

    if channel == selected_channel and note == selected_note do
      color
    else
      @inactive_note_color
    end
  end

  defp focus_color(_series_key, color, _selected_note_key), do: color

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
       Map.get(event, :chord_instance_id, 0), Map.get(event, :event_index, 999), event.note,
       event.channel}
    end)
  end

  defp note_series_key(note) do
    {
      Map.get(note, :sample_entry_index, -1),
      Map.get(note, :machine_id, :unknown),
      Map.get(note, :chord_instance_id, 0),
      Map.get(note, :event_index, 0),
      Map.get(note, :note, 0),
      Map.get(note, :channel, -1)
    }
  end

  defp series_channel_note(
         {_entry_index, _machine_id, _chord_instance_id, _event_index, note, channel}
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
        detail_total_mbeats =
          detail_total_mbeats(frames, duration_ms, socket.assigns.sample_context)

        socket
        |> assign(
          :pressure_chart,
          build_chart(
            frames,
            :pressure,
            {0, 127},
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.sample_context,
            detail_total_mbeats
          )
        )
        |> assign(
          :slide_chart,
          build_chart(
            frames,
            :slide,
            {0, 127},
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.sample_context,
            detail_total_mbeats
          )
        )
        |> assign(
          :bend_chart,
          build_chart(
            frames,
            :bend,
            value_range(frames),
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.sample_context,
            detail_total_mbeats
          )
        )
        |> assign(:debug_rows, debug_rows(frames))
        |> assign(
          :note_matrix,
          build_note_matrix(
            frames,
            socket.assigns.render_scope,
            socket.assigns.selected_note_key,
            socket.assigns.sample_context,
            detail_total_mbeats
          )
        )
        |> assign(
          :chart_grid,
          chart_grid_model(socket.assigns.sample_context, detail_total_mbeats)
        )
        |> assign(
          :note_matrix_grid,
          note_matrix_grid_model(socket.assigns.sample_context, detail_total_mbeats)
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
