defmodule MenschWeb.FullPianoKeyboard do
  @moduledoc """
  Shared full-range (88-key) piano visualization used across LiveViews.
  """

  use MenschWeb, :html

  alias Mensch.Harmony.ChordSpec

  @min_midi 21
  @max_midi 108

  attr :id, :string, required: true
  attr :keys, :list, required: true
  attr :height_class, :string, default: "h-40"
  attr :show_bottom_lane, :boolean, default: true
  attr :bottom_labels, :map, default: %{}
  attr :color_mode, :atom, default: :bright

  def keyboard(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "relative overflow-hidden rounded-md border border-zinc-700/70 bg-zinc-950",
        @height_class
      ]}
    >
      <%= for key <- @keys do %>
        <div
          :if={key.kind == :white}
          title={key.label}
          class={[
            "absolute border-r border-zinc-900 transition-colors duration-150",
            @show_bottom_lane && "bottom-6 top-0",
            !@show_bottom_lane && "inset-y-0",
            key.center_marker && "ring-2 ring-amber-400 ring-inset",
            key.outside_register && "opacity-35 saturate-50",
            key.tonic && "bg-[#f6d365]",
            !key.tonic && key.foreign_bass && "bg-[#ff4d6d]",
            !key.tonic && !key.foreign_bass && key.active && "bg-[#9bf25a]",
            !key.active && white_key_idle_class(@color_mode)
          ]}
          style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
        >
          <span
            :if={Map.get(key, :resolved_tone, false)}
            class="pointer-events-none absolute left-[32%] top-1 inline-block size-2 rounded-full bg-[#ff7a1a]"
          ></span>
          <span
            :if={Map.get(key, :inverted_tone, false)}
            class="pointer-events-none absolute left-[58%] top-1 inline-block size-2 rounded-full bg-[#75b8ff]"
          ></span>
          <span
            :if={Map.get(key, :voiced_tone, false)}
            class="pointer-events-none absolute left-[76%] top-1 inline-block size-2 rounded-full bg-[#2fd5c8]"
          ></span>
          <span class={[
            "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
            key.active && "text-zinc-900",
            !key.active && white_key_label_class(@color_mode)
          ]}>
            {key.midi}
          </span>
        </div>
      <% end %>

      <%= for key <- @keys do %>
        <div
          :if={key.kind == :black}
          title={key.label}
          class={[
            "absolute top-0 z-10 h-[62%] rounded-b-sm border border-black/70 transition-colors duration-150",
            key.center_marker && "ring-2 ring-amber-400 ring-inset",
            key.outside_register && "opacity-35 saturate-50",
            key.tonic && "bg-[#f6d365]",
            !key.tonic && key.foreign_bass && "bg-[#ff4d6d]",
            !key.tonic && !key.foreign_bass && key.active && "bg-[#9bf25a]",
            !key.active && black_key_idle_class(@color_mode)
          ]}
          style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
        >
          <span
            :if={Map.get(key, :resolved_tone, false)}
            class="pointer-events-none absolute left-[26%] top-1 inline-block size-1.5 rounded-full bg-[#ff7a1a]"
          ></span>
          <span
            :if={Map.get(key, :inverted_tone, false)}
            class="pointer-events-none absolute left-[58%] top-1 inline-block size-1.5 rounded-full bg-[#75b8ff]"
          ></span>
          <span
            :if={Map.get(key, :voiced_tone, false)}
            class="pointer-events-none absolute left-[78%] top-1 inline-block size-1.5 rounded-full bg-[#2fd5c8]"
          ></span>
          <span class={[
            "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
            key.active && "text-zinc-900",
            !key.active && black_key_label_class(@color_mode)
          ]}>
            {key.midi}
          </span>
        </div>
      <% end %>

      <div
        :if={@show_bottom_lane and map_size(@bottom_labels) > 0}
        class="pointer-events-none absolute inset-x-0 bottom-0 h-6"
      >
        <%= for key <- @keys do %>
          <span
            :if={Map.has_key?(@bottom_labels, key.midi)}
            class="absolute bottom-1 -translate-x-1/2 font-mono text-[10px] font-semibold text-[#9bf25a]"
            style={"left: calc(#{key.left_pct}% + #{key.width_pct / 2}%);"}
          >
            {Map.get(@bottom_labels, key.midi)}
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  @spec key_maps(keyword()) :: [map()]
  def key_maps(opts \\ []) do
    active_notes = opts |> Keyword.get(:active_notes, []) |> MapSet.new()
    tonic_notes = opts |> Keyword.get(:tonic_notes, []) |> MapSet.new()
    resolved_notes = opts |> Keyword.get(:resolved_notes, []) |> MapSet.new()
    inverted_notes = opts |> Keyword.get(:inverted_notes, []) |> MapSet.new()
    voiced_notes = opts |> Keyword.get(:voiced_notes, []) |> MapSet.new()
    foreign_bass_note = Keyword.get(opts, :foreign_bass_note)
    center_note = Keyword.get(opts, :center_note)
    range_min = Keyword.get(opts, :range_min)
    range_max = Keyword.get(opts, :range_max)

    white_midis = Enum.filter(@min_midi..@max_midi, &(not black_key?(&1)))
    total_whites = length(white_midis)
    white_width = 100.0 / total_whites
    black_width = white_width * 0.62

    Enum.map(@min_midi..@max_midi, fn midi ->
      white_before_or_at = Enum.count(@min_midi..midi, &(not black_key?(&1)))

      base = %{
        midi: midi,
        active: MapSet.member?(active_notes, midi),
        tonic: MapSet.member?(tonic_notes, midi),
        resolved_tone: MapSet.member?(resolved_notes, midi),
        inverted_tone: MapSet.member?(inverted_notes, midi),
        voiced_tone: MapSet.member?(voiced_notes, midi),
        foreign_bass: midi == foreign_bass_note,
        center_marker: is_integer(center_note) and midi == center_note,
        outside_register: outside_register?(midi, range_min, range_max),
        label: note_label(midi)
      }

      if black_key?(midi) do
        Map.merge(base, %{
          kind: :black,
          left_pct: white_before_or_at * white_width - black_width / 2,
          width_pct: black_width,
          show_octave_label: false
        })
      else
        left_pct = (white_before_or_at - 1) * white_width

        Map.merge(base, %{
          kind: :white,
          left_pct: left_pct,
          width_pct: white_width,
          show_octave_label: show_c_label?(midi)
        })
      end
    end)
  end

  defp note_label(midi_note) when is_integer(midi_note) do
    {name, octave} = ChordSpec.note_name(midi_note)
    "#{ChordSpec.root_label(name)}#{octave}"
  end

  defp outside_register?(midi_note, range_min, range_max) do
    below_min = is_integer(range_min) and midi_note < range_min
    above_max = is_integer(range_max) and midi_note > range_max
    below_min or above_max
  end

  defp white_key_idle_class(:dark), do: "bg-zinc-800"
  defp white_key_idle_class(_), do: "bg-zinc-100"

  defp black_key_idle_class(:dark), do: "bg-black"
  defp black_key_idle_class(_), do: "bg-zinc-900"

  defp white_key_label_class(:dark), do: "text-zinc-200"
  defp white_key_label_class(_), do: "text-zinc-500"

  defp black_key_label_class(:dark), do: "text-zinc-400"
  defp black_key_label_class(_), do: "text-zinc-300"

  defp show_c_label?(midi_note), do: rem(midi_note, 12) == 0
  defp black_key?(midi_note), do: rem(midi_note, 12) in [1, 3, 6, 8, 10]
end
