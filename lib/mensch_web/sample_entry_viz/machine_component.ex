defmodule MenschWeb.SampleEntryViz.MachineComponent do
  use MenschWeb, :html

  alias Mensch.Machine
  alias Mensch.Machines.ArpMachine
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.SimpleChord

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
          <dd>{value}</dd>
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
      {"attack_mbeats", params.attack_mbeats},
      {"decay_mbeats", params.decay_mbeats},
      {"release_mbeats", params.release_mbeats}
    ]
  end

  defp machine_params(machine) do
    [{"details", inspect(machine)}]
  end
end
