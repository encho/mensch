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
  @chart_colors ["#22c55e", "#3b82f6", "#f97316", "#ec4899"]

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
     |> assign(:view_modal_open, true)}
  end

  def handle_event("play_full_song", _params, socket) do
    entries = socket.assigns.song_entries
    song_context = socket.assigns.song_context
    render_data = Render.generate_song(entries, song_context)

    {:noreply, start_playback(assign(socket, :render_data, render_data), render_data)}
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
            {:noreply, start_playback(assign(socket, :render_data, render_data), render_data)}

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
    {:noreply, start_playback(socket, socket.assigns.render_data)}
  end

  def handle_event("stop", _params, socket) do
    Player.stop()

    socket =
      socket
      |> assign(:player_status, Player.status())
      |> assign(:play_started_at, nil)
      |> assign(:playhead_pct, nil)

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

    if status == :playing do
      Process.send_after(self(), :refresh_player, @refresh_interval_ms)
    end

    {:noreply, socket}
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

        %{music: music, duration_ms: duration_ms} ->
          assigns
          |> assign(
            :pressure_chart,
            build_chart(music, duration_ms, :pressure, {0, 127})
          )
          |> assign(:slide_chart, build_chart(music, duration_ms, :slide, {0, 127}))
          |> assign(:bend_chart, build_chart(music, duration_ms, :bend, value_range(music)))
          |> assign(:debug_rows, debug_rows(music))
          |> assign(:note_matrix, build_note_matrix(music, duration_ms))
      end

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
              class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-green-400 ring-1 ring-green-500/70 transition-colors duration-150 hover:ring-green-400 hover:text-green-300"
            >
              <.icon name="hero-play-solid" class="size-4" />
            </button>
            <button
              type="button"
              id="stop-full-song"
              aria-label="Stop full song"
              phx-click="stop"
              class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-red-400 ring-1 ring-red-500/70 transition-colors duration-150 hover:ring-red-400 hover:text-red-300"
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
                  <td class="px-2 py-1.5 text-white">{chord_label(entry.chord_spec)}</td>
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
                        class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-green-400 ring-1 ring-green-500/70 transition-colors duration-150 hover:ring-green-400 hover:text-green-300"
                      >
                        <.icon name="hero-play-solid" class="size-4" />
                      </button>
                      <button
                        type="button"
                        id={"stop-entry-#{index}"}
                        aria-label={"Stop #{chord_label(entry.chord_spec)}"}
                        phx-click="stop"
                        class="flex size-9 items-center justify-center border border-zinc-500 bg-transparent text-red-400 ring-1 ring-red-500/70 transition-colors duration-150 hover:ring-red-400 hover:text-red-300"
                      >
                        <.icon name="hero-stop-solid" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
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
                :if={@playhead_pct}
                class="pointer-events-none absolute inset-y-0 z-20 w-px bg-white/70"
                style={"left: #{@playhead_pct}%;"}
              >
              </div>
              <div
                :for={{row, index} <- Enum.with_index(@note_matrix)}
                class={[
                  "relative flex h-2.5 items-center border-b border-white/20 last:border-0",
                  rem(index, 2) == 0 && "bg-white/[0.03]"
                ]}
              >
                <div :if={row.style} class="absolute inset-0" style={row.style}></div>
                <span class={[
                  "relative z-10 px-1 font-mono text-[5px] uppercase",
                  (row.style && "text-white") || "text-white/30"
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

          <.chart title="Pressure" chart={@pressure_chart} playhead_pct={@playhead_pct} />
          <.chart
            title="Slide (Aftertouch)"
            chart={@slide_chart}
            playhead_pct={@playhead_pct}
          />
          <.chart title="Bend (Vibrato)" chart={@bend_chart} playhead_pct={@playhead_pct} />

          <div class="flex justify-center gap-3">
            <button
              type="button"
              id="play-button"
              aria-label="Play on Osmose"
              phx-click="play"
              class={[
                "flex size-14 items-center justify-center border border-zinc-500 bg-transparent transition-colors duration-150",
                (playing?(@player_status) && "text-white/20 ring-1 ring-white/10") ||
                  "text-green-400 ring-1 ring-green-500/70 hover:ring-green-400 hover:text-green-300",
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
                   "text-red-400 ring-1 ring-red-500/70 hover:ring-red-400 hover:text-red-300") ||
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

  attr :title, :string, required: true
  attr :chart, :list, required: true
  attr :playhead_pct, :any, default: nil

  defp chart(assigns) do
    ~H"""
    <div>
      <div class="mb-1 text-[11px] uppercase tracking-wide text-white/40">{@title}</div>
      <svg viewBox="0 0 600 120" class="w-full border border-white/10 bg-black">
        <polyline
          :for={series <- @chart}
          points={series.points}
          fill="none"
          stroke={series.color}
          stroke-width="1.5"
        />
        <line
          :if={@playhead_pct}
          x1={@playhead_pct / 100 * 600}
          x2={@playhead_pct / 100 * 600}
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

  # Groups a rendered `music` timeline's frames by note (`{channel,
  # note}`), one polyline per note, for an SVG line chart of `value_key`
  # (`:pressure`, `:bend`, or `:slide`) over time.
  defp build_chart(music, duration_ms, value_key, {min_v, max_v}) do
    colors = note_color_map(music)

    music
    |> Enum.flat_map(fn frame ->
      Enum.map(frame.notes, &{{&1.channel, &1.note}, frame.at_ms, Map.fetch!(&1, value_key)})
    end)
    |> Enum.group_by(
      fn {id, _at_ms, _value} -> id end,
      fn {_id, at_ms, value} -> {at_ms, value} end
    )
    |> Enum.map(fn {{channel, note}, points} ->
      %{
        channel: channel,
        note: note,
        color: Map.fetch!(colors, {channel, note}),
        points: chart_points(points, duration_ms, min_v, max_v)
      }
    end)
    |> Enum.sort_by(& &1.channel)
  end

  # A piano-roll style matrix: one row per semitone between the lowest
  # and highest sounding note (highest pitch on top), so the vertical
  # spacing between rows visually matches the actual chromatic distance
  # between the two chords - not just the notes that happen to sound.
  # Silent in-between notes get a row (dim label, no bar); sounding
  # notes get a bar spanning from their own (possibly staggered)
  # note-on to their note-off.
  defp build_note_matrix(music, duration_ms) do
    colors = note_color_map(music)
    duration_ms = max(duration_ms, 1)

    sounding =
      music
      |> Enum.flat_map(fn frame -> Enum.map(frame.notes, &{&1, frame.at_ms}) end)
      |> Enum.group_by(fn {note, _at_ms} -> note.note end)
      |> Map.new(fn {note_number, entries} ->
        {sample, _at_ms} = hd(entries)
        start_ms = entries |> Enum.find(fn {note, _} -> note.note_on end) |> elem(1)
        end_ms = entries |> Enum.find(fn {note, _} -> note.note_off end) |> elem(1)
        left_pct = start_ms / duration_ms * 100
        width_pct = max((end_ms - start_ms) / duration_ms * 100, 0.5)

        style =
          "left: #{Float.round(left_pct * 1.0, 2)}%; " <>
            "width: #{Float.round(width_pct * 1.0, 2)}%; " <>
            "background-color: #{Map.fetch!(colors, {sample.channel, note_number})};"

        {note_number, %{label: "#{sample.note_name}#{sample.octave}", style: style}}
      end)

    {min_note, max_note} = sounding |> Map.keys() |> Enum.min_max()

    for note_number <- max_note..min_note//-1 do
      case Map.fetch(sounding, note_number) do
        {:ok, row} ->
          Map.put(row, :note, note_number)

        :error ->
          {note_name, octave} = Render.note_name(note_number)
          %{note: note_number, label: "#{note_name}#{octave}", style: nil}
      end
    end
  end

  # Assigns each distinct `{channel, note}` a stable color (ordered by
  # channel) shared by both the line charts and the note matrix, so the
  # same note always reads as the same color across visualizations.
  defp note_color_map(music) do
    music
    |> Enum.flat_map(& &1.notes)
    |> Enum.uniq_by(&{&1.channel, &1.note})
    |> Enum.sort_by(& &1.channel)
    |> Enum.with_index()
    |> Map.new(fn {%{channel: channel, note: note}, index} ->
      {{channel, note}, Enum.at(@chart_colors, rem(index, length(@chart_colors)))}
    end)
  end

  defp chart_points(points, duration_ms, min_v, max_v) do
    range = max(max_v - min_v, 0.0001)
    duration_ms = max(duration_ms, 1)

    points
    |> Enum.sort_by(fn {at_ms, _value} -> at_ms end)
    |> Enum.map_join(" ", fn {at_ms, value} ->
      x = at_ms / duration_ms * 600
      y = 120 - (value - min_v) / range * 120
      "#{Float.round(x * 1.0, 1)},#{Float.round(y * 1.0, 1)}"
    end)
  end

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
