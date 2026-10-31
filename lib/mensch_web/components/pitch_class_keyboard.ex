defmodule MenschWeb.PitchClassKeyboard do
  @moduledoc """
  Reusable mini keyboard for selecting a pitch class.
  """

  use MenschWeb, :html

  @keyboard_keys [
    %{root: "c", kind: :white, left: 0.0, width: 14.2857, label: "C"},
    %{root: "d_flat", kind: :black, left: 9.5, width: 9.0, label: "Db"},
    %{root: "d", kind: :white, left: 14.2857, width: 14.2857, label: "D"},
    %{root: "e_flat", kind: :black, left: 23.8, width: 9.0, label: "Eb"},
    %{root: "e", kind: :white, left: 28.5714, width: 14.2857, label: "E"},
    %{root: "f", kind: :white, left: 42.8571, width: 14.2857, label: "F"},
    %{root: "g_flat", kind: :black, left: 52.3, width: 9.0, label: "Gb"},
    %{root: "g", kind: :white, left: 57.1428, width: 14.2857, label: "G"},
    %{root: "a_flat", kind: :black, left: 66.6, width: 9.0, label: "Ab"},
    %{root: "a", kind: :white, left: 71.4285, width: 14.2857, label: "A"},
    %{root: "b_flat", kind: :black, left: 80.9, width: 9.0, label: "Bb"},
    %{root: "b", kind: :white, left: 85.7142, width: 14.2857, label: "B"}
  ]

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :selected_key, :string, default: nil
  attr :show_clear, :boolean, default: false
  attr :clear_label, :string, default: "Clear"
  attr :header_action, :boolean, default: false
  attr :header_action_label, :string, default: nil
  attr :header_action_value, :string, default: ""
  attr :selected_key_color, :string, default: "#9bf25a"
  attr :value_index, :any, default: nil
  attr :value_field, :string, default: nil

  def mini(assigns) do
    assigns = assign(assigns, :keyboard_keys, @keyboard_keys)

    ~H"""
    <div id={@id} class="space-y-1">
      <div class="flex items-center justify-between gap-2">
        <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">{@label}</label>
        <button
          :if={@header_action}
          type="button"
          phx-click={@event}
          phx-value-pitch_class={@header_action_value}
          phx-value-index={@value_index}
          phx-value-field={@value_field}
          class="rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-[10px] text-zinc-300 hover:border-zinc-500"
        >
          {@header_action_label || @clear_label}
        </button>
      </div>
      <div class="relative h-24 w-full overflow-hidden rounded-md border border-zinc-700/70 bg-zinc-950/60 p-1">
        <button
          :for={key <- @keyboard_keys}
          type="button"
          phx-click={@event}
          phx-value-pitch_class={key.root}
          phx-value-index={@value_index}
          phx-value-field={@value_field}
          title={key.label}
          class={[
            "absolute border transition-colors duration-150",
            key.kind == :white && "rounded-sm",
            key.kind == :black && "rounded-b-sm rounded-t-none",
            key.kind == :white && "inset-y-1",
            @selected_key == key.root && "text-zinc-950",
            key.kind == :white && @selected_key != key.root &&
              "border-zinc-700 bg-zinc-100 text-zinc-800",
            key.kind == :black && "top-1 z-10 h-[50%]",
            key.kind == :black && @selected_key != key.root &&
              "border-black/70 bg-zinc-900 text-zinc-100"
          ]}
          style={"left: #{key.left}%; width: #{key.width}%; #{selected_key_style(@selected_key, key.root, @selected_key_color)}"}
        >
          <span class={[
            "pointer-events-none text-[10px] font-mono font-semibold",
            key.kind == :black && @selected_key == key.root && "text-zinc-950",
            key.kind == :black && @selected_key != key.root && "text-zinc-100",
            key.kind == :white && @selected_key == key.root && "text-emerald-950",
            key.kind == :white && @selected_key != key.root && "text-zinc-800"
          ]}>
            {key.label}
          </span>
        </button>
      </div>

      <div :if={@show_clear and not @header_action} class="flex justify-end">
        <button
          type="button"
          phx-click={@event}
          phx-value-pitch_class=""
          phx-value-index={@value_index}
          phx-value-field={@value_field}
          class="rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-[10px] text-zinc-300 hover:border-zinc-500"
        >
          {@clear_label}
        </button>
      </div>
    </div>
    """
  end

  defp selected_key_style(selected_key, key_root, selected_key_color)
       when selected_key == key_root and is_binary(selected_key_color) do
    "background-color: #{selected_key_color}; border-color: #{selected_key_color};"
  end

  defp selected_key_style(_selected_key, _key_root, _selected_key_color), do: ""
end
