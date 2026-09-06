defmodule MenschWeb.HomeLive.DetailPanelComponent do
  use MenschWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 border border-zinc-700/60 bg-zinc-950/75 p-4">
      <div id="note-matrix" class="border border-zinc-700/60">
        <div class="flex items-center justify-between gap-3 border-b border-zinc-700/60 px-3 py-1.5">
          <div class="text-[11px] uppercase tracking-wide text-zinc-400">Note matrix</div>
          <div class="flex items-center gap-3 font-mono text-[10px] text-zinc-500">
            <span>Focus: {@selected_note_label}</span>
            <button
              :if={not is_nil(@selected_note_key)}
              type="button"
              phx-click="clear_note_focus"
              class="border border-zinc-600 px-2 py-0.5 text-[10px] uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-amber-400 hover:text-amber-200"
            >
              Clear
            </button>
          </div>
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
            :for={{row, index} <- Enum.with_index(@note_matrix)}
            class={[
              "relative z-10 flex h-2.5 items-center border-b border-zinc-700/60 last:border-0",
              rem(index, 2) == 0 && "bg-zinc-900/70"
            ]}
          >
            <div
              :for={segment <- Map.get(row, :segments, [])}
              phx-click="toggle_note_focus"
              phx-value-note={to_string(segment.note)}
              phx-value-channel={to_string(segment.channel)}
              class={[
                "absolute inset-y-0 z-20 cursor-pointer transition-opacity duration-150",
                segment.active && "opacity-100",
                !segment.active && "opacity-70"
              ]}
              style={segment.style}
            >
            </div>
            <span class={[
              "relative z-10 px-1 font-mono text-[5px] uppercase",
              (Enum.empty?(Map.get(row, :segments, [])) && "text-zinc-600") ||
                (Map.get(row, :has_active_segment, false) && "text-zinc-200") ||
                "text-zinc-500"
            ]}>
              {row.label}
            </span>
          </div>
        </div>
        <div class="flex justify-between px-3 pb-2 pt-1 font-mono text-[10px] text-zinc-500">
          <span>{@timeline_start_label}</span>
          <span>{@timeline_end_label}</span>
        </div>
      </div>

      <.chart title="Pressure" chart={@pressure_chart} grid={@chart_grid} />
      <.chart title="Slide (Aftertouch)" chart={@slide_chart} grid={@chart_grid} />
      <.chart title="Bend (Vibrato)" chart={@bend_chart} grid={@chart_grid} />

      <div class="text-[11px] uppercase tracking-wide text-zinc-400">Rendered frames and curves</div>

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
    </div>
    """
  end

  attr :title, :string, required: true
  attr :chart, :list, required: true
  attr :grid, :map, required: true

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
      </svg>
    </div>
    """
  end

  defp format_bend(bend), do: Float.round(bend * 1.0, 5)
end
