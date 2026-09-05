defmodule MenschWeb.HomeLive do
  @moduledoc """
  Root LiveView for Mensch.

  Owns the editable `Mensch.Project` configuration (tempo, key, chord
  duration, progression, machine, output mode) directly on the socket.
  Harmony resolution and performance generation are pure domain
  functions — this LiveView only calls them, it never implements them.

  For this iteration, PLAY does not run a real-time scheduler: it
  resolves the whole progression and displays the resulting
  performance timeline once.
  """

  use MenschWeb, :live_view

  alias Mensch.Harmony.{ChordSpec, Key}
  alias Mensch.Machine.RootNote
  alias Mensch.Machine.RootNoteMpe
  alias Mensch.Midi.Writer
  alias Mensch.Output
  alias Mensch.Performance.Engine
  alias Mensch.Project

  @root_options [
    {"C", "c"},
    {"C#", "c_sharp"},
    {"D", "d"},
    {"D#", "d_sharp"},
    {"E", "e"},
    {"F", "f"},
    {"F#", "f_sharp"},
    {"G", "g"},
    {"G#", "g_sharp"},
    {"A", "a"},
    {"A#", "a_sharp"},
    {"B", "b"}
  ]
  @root_values Map.new(@root_options, fn {_label, value} -> {value, String.to_atom(value)} end)

  @degree_options [
    {"I", "I"},
    {"ii", "ii"},
    {"iii", "iii"},
    {"IV", "IV"},
    {"V", "V"},
    {"vi", "vi"},
    {"vii", "vii"}
  ]
  @degree_values Map.new(@degree_options, fn {_label, value} -> {value, String.to_atom(value)} end)

  @modifier_options [{"min7", "min7"}, {"dom7", "dom7"}, {"maj7", "maj7"}]
  @modifier_values Map.new(@modifier_options, fn {_label, value} ->
                     {value, String.to_atom(value)}
                   end)

  @output_options [{"MIDI", "midi"}, {"MPE", "mpe"}]
  @output_values Map.new(@output_options, fn {_label, value} -> {value, String.to_atom(value)} end)

  @machine_options [{"ROOT_NOTE", "root_note"}, {"ROOT_NOTE_MPE", "root_note_mpe"}]

  @note_labels %{
    c: "C",
    c_sharp: "C#",
    d: "D",
    d_sharp: "D#",
    e: "E",
    f: "F",
    f_sharp: "F#",
    g: "G",
    g_sharp: "G#",
    a: "A",
    a_sharp: "A#",
    b: "B"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, project: Project.default(), events: nil)}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    project = project_from_params(socket.assigns.project, params)
    {:noreply, assign(socket, project: project, events: nil)}
  end

  @impl true
  def handle_event("play", %{"project" => params}, socket) do
    project = project_from_params(socket.assigns.project, params)
    events = Engine.generate(project)
    {:noreply, assign(socket, project: project, events: events)}
  end

  @impl true
  def handle_event("download_midi", _params, socket) do
    case socket.assigns.events do
      nil ->
        {:noreply, socket}

      events ->
        midi_binary = Writer.encode(events, socket.assigns.project.bpm)

        {:noreply,
         push_event(socket, "download_midi", %{
           data: Base.encode64(midi_binary),
           filename: "mensch-performance.mid"
         })}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-neutral-950 px-6 py-10 font-sans text-neutral-100">
        <div class="mx-auto max-w-2xl">
          <header class="mb-8">
            <h1 class="text-2xl font-semibold tracking-[0.3em] text-neutral-50">MENSCH</h1>
          </header>

          <form phx-change="validate" phx-submit="play" class="space-y-8">
            <.field label="BPM">
              <input
                type="number"
                name="project[bpm]"
                value={@project.bpm}
                min="1"
                phx-debounce="blur"
                class={input_class()}
              />
            </.field>

            <.field label="Key">
              <div class="flex gap-2">
                <select name="project[key_root]" class={input_class()}>
                  <option
                    :for={{label, value} <- root_options()}
                    value={value}
                    selected={value == to_string(@project.key.root)}
                  >
                    {label}
                  </option>
                </select>
                <span class={static_value_class()}>Major</span>
              </div>
            </.field>

            <.field label="Chord Duration">
              <div class="flex items-center gap-2">
                <input
                  type="number"
                  name="project[chord_duration]"
                  value={chord_duration_beats(@project)}
                  min="0.25"
                  step="0.25"
                  phx-debounce="blur"
                  class={input_class()}
                />
                <span class="text-xs uppercase tracking-widest text-neutral-500">beats</span>
              </div>
            </.field>

            <fieldset>
              <legend class={label_class()}>Progression</legend>
              <div class="mt-2 space-y-2">
                <div
                  :for={{chord_spec, index} <- Enum.with_index(@project.progression)}
                  class="flex items-center gap-2"
                >
                  <span class="w-5 text-xs text-neutral-500">{index + 1}</span>
                  <select name={"project[progression][#{index}][degree]"} class={input_class()}>
                    <option
                      :for={{label, value} <- degree_options()}
                      value={value}
                      selected={value == to_string(chord_spec.degree)}
                    >
                      {label}
                    </option>
                  </select>
                  <select name={"project[progression][#{index}][modifier]"} class={input_class()}>
                    <option
                      :for={{label, value} <- modifier_options()}
                      value={value}
                      selected={value == to_string(chord_spec.modifier)}
                    >
                      {label}
                    </option>
                  </select>
                </div>
              </div>
            </fieldset>

            <.field label="Machine">
              <select name="project[machine][kind]" class={input_class()}>
                <option
                  :for={{label, value} <- machine_options()}
                  value={value}
                  selected={value == machine_kind(@project.machine)}
                >
                  {label}
                </option>
              </select>
            </.field>

            <fieldset>
              <legend class={label_class()}>{machine_kind_label(@project.machine)} Parameters</legend>
              <div class="mt-2 space-y-2">
                <.field label="Octave" nested>
                  <input
                    type="number"
                    name="project[machine][octave]"
                    value={@project.machine.octave}
                    min="0"
                    max="9"
                    phx-debounce="blur"
                    class={input_class()}
                  />
                </.field>
                <.field label="Velocity" nested>
                  <input
                    type="number"
                    name="project[machine][velocity]"
                    value={@project.machine.velocity}
                    min="0"
                    max="127"
                    phx-debounce="blur"
                    class={input_class()}
                  />
                </.field>
                <.field label="Note Length" nested>
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      name="project[machine][note_length]"
                      value={round(@project.machine.note_length * 100)}
                      min="1"
                      phx-debounce="blur"
                      class={input_class()}
                    />
                    <span class="text-xs uppercase tracking-widest text-neutral-500">%</span>
                  </div>
                </.field>
                <.field :if={match?(%RootNoteMpe{}, @project.machine)} label="Pressure Depth" nested>
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      name="project[machine][pressure_depth]"
                      value={round(@project.machine.pressure_depth * 100)}
                      min="0"
                      max="100"
                      phx-debounce="blur"
                      class={input_class()}
                    />
                    <span class="text-xs uppercase tracking-widest text-neutral-500">%</span>
                  </div>
                </.field>
                <.field
                  :if={match?(%RootNoteMpe{}, @project.machine)}
                  label="Pitch Bend Depth"
                  nested
                >
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      name="project[machine][pitch_bend_depth]"
                      value={@project.machine.pitch_bend_depth}
                      min="0"
                      max="48"
                      step="0.5"
                      phx-debounce="blur"
                      class={input_class()}
                    />
                    <span class="text-xs uppercase tracking-widest text-neutral-500">semitones</span>
                  </div>
                </.field>
              </div>
            </fieldset>

            <.field label="Output">
              <select name="project[output_mode]" class={input_class()}>
                <option
                  :for={{label, value} <- output_options()}
                  value={value}
                  selected={value == to_string(@project.output.mode)}
                >
                  {label}
                </option>
              </select>
            </.field>

            <button
              type="submit"
              class="w-full rounded-md border border-amber-500/70 bg-amber-500/10 py-2 text-xs font-semibold uppercase tracking-widest text-amber-400 transition-colors hover:bg-amber-500/20"
            >
              Play
            </button>
          </form>

          <section
            :if={@events}
            class="mt-10 rounded-md border border-neutral-800 bg-neutral-900/40 p-4"
          >
            <div class="flex items-center justify-between">
              <h2 class="text-xs font-semibold uppercase tracking-widest text-neutral-400">
                Generated Performance
              </h2>
              <button
                type="button"
                phx-click="download_midi"
                class="rounded-md border border-neutral-700 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-neutral-300 transition-colors hover:border-neutral-500"
              >
                Download MIDI
              </button>
            </div>
            <ul class="mt-3 space-y-1 font-mono text-sm text-neutral-200">
              <li :for={event <- @events}>{format_event(event)}</li>
            </ul>
          </section>

          <div id="midi-download" phx-hook=".MidiDownload"></div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".MidiDownload">
            export default {
              mounted() {
                this.handleEvent("download_midi", ({ data, filename }) => {
                  const binary = window.atob(data)
                  const bytes = new Uint8Array(binary.length)
                  for (let i = 0; i < binary.length; i++) {
                    bytes[i] = binary.charCodeAt(i)
                  }

                  const blob = new Blob([bytes], { type: "audio/midi" })
                  const url = URL.createObjectURL(blob)
                  const link = document.createElement("a")
                  link.href = url
                  link.download = filename
                  document.body.appendChild(link)
                  link.click()
                  document.body.removeChild(link)
                  URL.revokeObjectURL(url)
                })
              }
            }
          </script>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :nested, :boolean, default: false
  slot :inner_block, required: true

  defp field(assigns) do
    ~H"""
    <div>
      <div class={label_class()}>{@label}</div>
      <div class={["mt-1", @nested && "max-w-40"]}>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp root_options, do: @root_options
  defp degree_options, do: @degree_options
  defp modifier_options, do: @modifier_options
  defp output_options, do: @output_options
  defp machine_options, do: @machine_options

  defp machine_kind(%RootNote{}), do: "root_note"
  defp machine_kind(%RootNoteMpe{}), do: "root_note_mpe"

  defp machine_kind_label(%RootNote{}), do: "Root Note"
  defp machine_kind_label(%RootNoteMpe{}), do: "Root Note Mpe"

  defp label_class, do: "text-xs font-semibold uppercase tracking-widest text-neutral-500"

  defp static_value_class, do: "text-sm text-neutral-300"

  defp input_class do
    "rounded-md border border-neutral-800 bg-neutral-900 px-2 py-1 text-sm text-neutral-100 focus:border-neutral-600 focus:outline-none"
  end

  defp chord_duration_beats(%Project{chord_duration: {:beats, beats}}), do: beats

  defp format_event(%{type: :note_on, at_beat: at_beat, note: note, velocity: velocity}) do
    "#{format_beat(at_beat)}   #{format_note(note)} ON velocity #{velocity}"
  end

  defp format_event(%{type: :note_off, at_beat: at_beat, note: note}) do
    "#{format_beat(at_beat)}   #{format_note(note)} OFF"
  end

  defp format_event(%{type: :pressure, at_beat: at_beat, note: note, value: value}) do
    "#{format_beat(at_beat)}   #{format_note(note)} PRESSURE #{format_percent(value)}"
  end

  defp format_event(%{type: :pitch_bend, at_beat: at_beat, note: note, value: value}) do
    "#{format_beat(at_beat)}   #{format_note(note)} PITCH #{format_semitones(value)}"
  end

  defp format_beat(beat), do: :erlang.float_to_binary(beat, decimals: 1)

  defp format_percent(value), do: "#{round(value * 100)}%"

  defp format_semitones(value) do
    sign = if value >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(value * 1.0, decimals: 2)}st"
  end

  defp format_note({name, octave}), do: "#{Map.fetch!(@note_labels, name)}#{octave}"

  defp project_from_params(%Project{} = project, params) do
    %{
      project
      | bpm: parse_integer(params["bpm"], project.bpm),
        key: parse_key(params["key_root"], project.key),
        chord_duration: parse_chord_duration(params["chord_duration"], project.chord_duration),
        progression: parse_progression(params["progression"], project.progression),
        machine: parse_machine(params["machine"], project.machine),
        output: parse_output(params["output_mode"], project.output)
    }
  end

  defp parse_key(root, %Key{} = key) do
    case Map.fetch(@root_values, root) do
      {:ok, value} -> %{key | root: value}
      :error -> key
    end
  end

  defp parse_chord_duration(beats, {:beats, current_beats}) do
    {:beats, parse_float(beats, current_beats)}
  end

  defp parse_progression(rows, current_progression) when is_list(rows) do
    current_progression
    |> Enum.with_index()
    |> Enum.map(fn {chord_spec, index} ->
      case Enum.at(rows, index) do
        nil -> chord_spec
        row -> parse_chord_spec(row, chord_spec)
      end
    end)
  end

  defp parse_progression(_rows, current_progression), do: current_progression

  defp parse_chord_spec(row, %ChordSpec{} = chord_spec) do
    degree = Map.get(@degree_values, row["degree"], chord_spec.degree)
    modifier = Map.get(@modifier_values, row["modifier"], chord_spec.modifier)
    %ChordSpec{degree: degree, modifier: modifier}
  end

  defp parse_machine(nil, machine), do: machine

  defp parse_machine(params, machine) do
    case Map.get(params, "kind", machine_kind(machine)) do
      "root_note_mpe" -> parse_root_note_mpe(params, machine)
      _ -> parse_root_note(params, machine)
    end
  end

  defp parse_root_note(params, machine) do
    %RootNote{
      octave: parse_integer(params["octave"], machine.octave),
      velocity: parse_integer(params["velocity"], machine.velocity) |> clamp(0, 127),
      note_length: parse_percent(params["note_length"], machine.note_length)
    }
  end

  defp parse_root_note_mpe(params, machine) do
    %RootNoteMpe{
      octave: parse_integer(params["octave"], machine.octave),
      velocity: parse_integer(params["velocity"], machine.velocity) |> clamp(0, 127),
      note_length: parse_percent(params["note_length"], machine.note_length),
      pressure_depth: parse_percent(params["pressure_depth"], existing_pressure_depth(machine)),
      pitch_bend_depth:
        parse_float(params["pitch_bend_depth"], existing_pitch_bend_depth(machine))
    }
  end

  defp existing_pressure_depth(%RootNoteMpe{pressure_depth: value}), do: value
  defp existing_pressure_depth(_machine), do: %RootNoteMpe{}.pressure_depth

  defp existing_pitch_bend_depth(%RootNoteMpe{pitch_bend_depth: value}), do: value
  defp existing_pitch_bend_depth(_machine), do: %RootNoteMpe{}.pitch_bend_depth

  defp parse_output(mode, %Output{} = output) do
    case Map.fetch(@output_values, mode) do
      {:ok, value} -> %{output | mode: value}
      :error -> output
    end
  end

  defp parse_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_float(value, default) do
    case Float.parse(to_string(value)) do
      {float, _} ->
        float

      :error ->
        case Integer.parse(to_string(value)) do
          {int, _} -> int * 1.0
          :error -> default
        end
    end
  end

  defp parse_percent(value, default) do
    case Integer.parse(to_string(value)) do
      {percent, _} -> percent / 100.0
      :error -> default
    end
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
