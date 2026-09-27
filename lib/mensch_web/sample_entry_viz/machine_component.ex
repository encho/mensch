defmodule MenschWeb.SampleEntryViz.MachineComponent do
  use MenschWeb, :html

  alias Mensch.Machine
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.RootNote

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

  defp machine_params(%DynamicVoicing{params: params, modulation_strategy: modulation_strategy}) do
    [
      {"direction", inspect(params.direction)},
      {"number_of_inversions", params.number_of_inversions},
      {"note_modulation_strategy", inspect(modulation_strategy.__struct__)}
    ]
  end

  defp machine_params(%RootNote{params: params, modulation_strategy: modulation_strategy}) do
    [
      {"octave_offset", params.octave_offset},
      {"velocity", params.velocity},
      {"pressure", params.pressure},
      {"note_modulation_strategy", inspect(modulation_strategy.__struct__)}
    ]
  end

  defp machine_params(machine) do
    [{"details", inspect(machine)}]
  end
end
