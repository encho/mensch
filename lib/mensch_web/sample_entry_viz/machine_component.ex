defmodule MenschWeb.SampleEntryViz.MachineComponent do
  use MenschWeb, :html

  alias Mensch.Machine
  alias Mensch.Machines.ArpMachine
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.SimpleChord
  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoGroup
  alias Mensch.NewModulation.LfoRamp
  alias Mensch.NewModulation.LfoSaw

  attr :machine, :map, required: true

  def panel(assigns) do
    assigns =
      assign(assigns,
        machine_name: machine_name(assigns.machine),
        machine_params: machine_params(assigns.machine)
      )

    ~H"""
    <section class="ui-radius-card border border-zinc-800 bg-zinc-900/50 p-3">
      <div class="mb-2 text-[11px] uppercase tracking-wide text-zinc-400">Machine</div>
      <div class="mb-2 font-mono text-[11px] text-zinc-100">{@machine_name}</div>

      <dl class="grid grid-cols-2 gap-x-4 gap-y-1 font-mono text-[11px] text-zinc-200">
        <%= for {label, value} <- @machine_params do %>
          <dt class="text-zinc-500">{label}</dt>
          <dd class="whitespace-pre-wrap wrap-break-word">{value}</dd>
        <% end %>
      </dl>
    </section>
    """
  end

  defp machine_name(machine) do
    machine
    |> Machine.id()
    |> Atom.to_string()
  end

  defp machine_params(%DynamicVoicing{params: params}) do
    [
      {"direction", inspect(params.direction)},
      {"number_of_inversions", params.number_of_inversions}
    ]
  end

  defp machine_params(%ArpMachine{params: params}) do
    [
      {"direction", inspect(params.direction)},
      {"stagger_mbeats", params.stagger_mbeats},
      {"octave_min_offset", params.octave_min_offset},
      {"octave_max_offset", params.octave_max_offset},
      {"cycle_count", params.cycle_count},
      {"note_length_mode", inspect(params.note_length_mode)}
    ]
  end

  defp machine_params(%SimpleChord{params: params}) do
    [
      {"stagger_mbeats", params.stagger_mbeats},
      {"note_length_mode", inspect(params.note_length_mode)},
      {"attack_mbeats", params.attack_mbeats},
      {"decay_mbeats", params.decay_mbeats},
      {"release_mbeats", params.release_mbeats}
    ]
  end

  defp machine_params(%RootNote{params: params}) do
    [
      {"octave_offset", params.octave_offset},
      {"velocity", params.velocity},
      {"pressure", params.pressure},
      {"lfo_pressure", format_lfo_pressure(params.lfo_pressure)}
    ]
  end

  defp machine_params(machine) do
    [{"details", inspect(machine)}]
  end

  defp format_lfo_pressure(%{mode: mode, lfo: lfo}) do
    [
      "mode: #{format_scalar(mode)}",
      "lfo:",
      indent(format_lfo_term(lfo), 2)
    ]
    |> Enum.join("\n")
  end

  defp format_lfo_pressure(other), do: inspect(other)

  defp format_lfo_term(%LfoGroup{} = group) do
    operations_text =
      case group.operations do
        [] -> "[]"
        operations -> Enum.map_join(operations, "\n", &format_lfo_operation/1)
      end

    [
      "group:",
      "  initial:",
      indent(format_lfo_term(group.initial), 4),
      "  operations:",
      indent(operations_text, 4)
    ]
    |> Enum.join("\n")
  end

  defp format_lfo_term(%LfoCurve{} = curve) do
    [
      "curve:",
      "  curve: #{format_scalar(curve.curve)}",
      "  scale: #{curve.scale}",
      "  cycles_per_bar: #{curve.cycles_per_bar}",
      "  shift_mbeats: #{curve.shift_mbeats}",
      "  polarity: #{format_scalar(curve.polarity)}",
      "  anchor: #{format_scalar(curve.anchor)}"
    ]
    |> Enum.join("\n")
  end

  defp format_lfo_term(%LfoSaw{} = saw) do
    [
      "saw:",
      "  curve: #{format_scalar(saw.curve)}",
      "  scale: #{saw.scale}",
      "  cycles_per_bar: #{saw.cycles_per_bar}",
      "  shift_mbeats: #{saw.shift_mbeats}",
      "  polarity: #{format_scalar(saw.polarity)}",
      "  anchor: #{format_scalar(saw.anchor)}",
      "  drop_phase: #{saw.drop_phase}"
    ]
    |> Enum.join("\n")
  end

  defp format_lfo_term(%LfoRamp{} = ramp) do
    [
      "ramp:",
      "  start_value: #{ramp.start_value}",
      "  end_value: #{ramp.end_value}",
      "  interpolation_function: #{format_scalar(ramp.interpolation_function)}",
      "  span_mbeats: #{ramp.span_mbeats}",
      "  shift_mbeats: #{ramp.shift_mbeats}",
      "  anchor: #{format_scalar(ramp.anchor)}"
    ]
    |> Enum.join("\n")
  end

  defp format_lfo_term(other), do: inspect(other)

  defp format_lfo_operation({op, term}) when op in [:add, :multiply] do
    [
      "- #{format_scalar(op)}:",
      indent(format_lfo_term(term), 2)
    ]
    |> Enum.join("\n")
  end

  defp format_lfo_operation(other), do: "- #{inspect(other)}"

  defp indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> pad <> line end)
  end

  defp format_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp format_scalar(value), do: to_string(value)
end
