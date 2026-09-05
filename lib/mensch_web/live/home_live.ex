defmodule MenschWeb.HomeLive do
  @moduledoc """
  Minimal UI: RENDER precomputes the full MPE performance for a
  hardcoded C4 maj7 chord (see `Mensch.Render`), showing its pressure/
  slide/bend curves as line charts. PLAY then dispatches that
  precomputed data in real time to the connected MIDI output (e.g. an
  Osmose); STOP silences it immediately.
  """

  use MenschWeb, :live_view

  alias Mensch.Player
  alias Mensch.Render

  @refresh_interval_ms 100
  @chart_colors ["#22c55e", "#3b82f6", "#f97316", "#ec4899"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:render_data, nil)
      |> assign(:player_status, Player.status())

    {:ok, socket}
  end

  @impl true
  def handle_event("render", _params, socket) do
    {:noreply, assign(socket, :render_data, Render.generate())}
  end

  def handle_event("play", _params, %{assigns: %{render_data: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("play", _params, socket) do
    Player.play(socket.assigns.render_data)
    Process.send_after(self(), :refresh_player, @refresh_interval_ms)
    {:noreply, assign(socket, :player_status, Player.status())}
  end

  def handle_event("stop", _params, socket) do
    Player.stop()
    {:noreply, assign(socket, :player_status, Player.status())}
  end

  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_info(:refresh_player, socket) do
    status = Player.status()
    socket = assign(socket, :player_status, status)

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
      <div class="mx-auto max-w-2xl space-y-6">
        <div id="render-section" class="space-y-4 border border-white/15 p-4">
          <div class="flex items-center justify-between text-[11px] uppercase tracking-wide text-white/40">
            <span>C4 maj7</span>
            <button
              type="button"
              id="render-button"
              phx-click="render"
              class="border border-white/30 px-3 py-1.5 text-white/70 transition-colors duration-150 hover:border-white hover:text-white"
            >
              Render
            </button>
          </div>

          <div :if={@render_data} class="space-y-4">
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
              <div class="space-y-1 px-3 py-2">
                <div :for={row <- @note_matrix} class="flex items-center gap-3">
                  <div class="w-10 shrink-0 font-mono text-[11px] text-white">{row.label}</div>
                  <div class="relative h-3 flex-1 bg-white/5">
                    <div class="absolute inset-y-0 rounded-[1px]" style={row.style}></div>
                  </div>
                </div>
              </div>
              <div class="flex justify-between px-3 pb-2 font-mono text-[10px] text-white/30">
                <span>0ms</span>
                <span>{@render_data.duration_ms}ms</span>
              </div>
            </div>

            <.chart title="Pressure" chart={@pressure_chart} />
            <.chart title="Slide (Aftertouch)" chart={@slide_chart} />
            <.chart title="Bend (Vibrato)" chart={@bend_chart} />

            <div class="flex gap-3">
              <button
                type="button"
                id="play-button"
                aria-label="Play on Osmose"
                phx-click="play"
                class={[
                  "flex flex-1 items-center justify-center border py-3 transition-colors duration-150",
                  (playing?(@player_status) && "border-white/15 text-white/15") ||
                    "border-green-500 text-green-500 hover:bg-green-500 hover:text-black",
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
                  "flex flex-1 items-center justify-center border py-3 transition-colors duration-150",
                  (playing?(@player_status) &&
                     "border-red-500 text-red-500 hover:bg-red-500 hover:text-black") ||
                    "border-white/15 text-white/15",
                  "disabled:cursor-not-allowed"
                ]}
                disabled={!playing?(@player_status)}
              >
                <.icon name="hero-stop-solid" class="size-6" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :chart, :list, required: true

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
      </svg>
    </div>
    """
  end

  defp playing?(player_status), do: player_status == :playing

  # Flattens every frame (one row per note) for a raw, at-a-glance table
  # of exactly what the note-on/pressure/bend/slide sequence looks like
  # across the whole chord performance.
  defp debug_rows(music) do
    Enum.flat_map(music, fn frame ->
      Enum.map(frame.notes, &Map.put(&1, :at_ms, frame.at_ms))
    end)
  end

  defp format_bend(bend), do: Float.round(bend * 1.0, 5)

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

  # A piano-roll style matrix: one row per discrete note (highest pitch
  # on top), spanning the ms range it's actually sounding, so note
  # events can be read off by eye against a shared time axis alongside
  # the line charts above.
  defp build_note_matrix(music, duration_ms) do
    colors = note_color_map(music)
    duration_ms = max(duration_ms, 1)

    music
    |> Enum.flat_map(fn frame -> Enum.map(frame.notes, &{&1, frame.at_ms}) end)
    |> Enum.group_by(fn {note, _at_ms} -> {note.channel, note.note} end)
    |> Enum.map(fn {{channel, note_number}, entries} ->
      {sample, _at_ms} = hd(entries)
      at_ms_values = Enum.map(entries, fn {_note, at_ms} -> at_ms end)
      start_ms = Enum.min(at_ms_values)
      end_ms = Enum.max(at_ms_values)
      left_pct = start_ms / duration_ms * 100
      width_pct = max((end_ms - start_ms) / duration_ms * 100, 0.5)

      %{
        note: note_number,
        label: "#{sample.note_name}#{sample.octave}",
        style:
          "left: #{Float.round(left_pct * 1.0, 2)}%; " <>
            "width: #{Float.round(width_pct * 1.0, 2)}%; " <>
            "background-color: #{Map.fetch!(colors, {channel, note_number})};"
      }
    end)
    |> Enum.sort_by(& &1.note, :desc)
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
