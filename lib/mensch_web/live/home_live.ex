defmodule MenschWeb.HomeLive do
  @moduledoc """
  Minimal live-performance UI: pick two chords, then PLAY starts a
  global loop that holds each chord for 4 bars before automatically
  advancing to the next (wrapping back to the first), sounding live on
  the connected MPE MIDI output (e.g. an Osmose). STOP halts the loop
  immediately, wherever it currently is.
  """

  use MenschWeb, :live_view

  alias Mensch.Chord
  alias Mensch.Harmony.Key
  alias Mensch.Sequencer

  @root_options [
    {"C", :c},
    {"C#", :c_sharp},
    {"D", :d},
    {"D#", :d_sharp},
    {"E", :e},
    {"F", :f},
    {"F#", :f_sharp},
    {"G", :g},
    {"G#", :g_sharp},
    {"A", :a},
    {"A#", :a_sharp},
    {"B", :b}
  ]

  @degree_options [
    {"I", :I},
    {"ii", :ii},
    {"iii", :iii},
    {"IV", :IV},
    {"V", :V},
    {"vi", :vi},
    {"vii", :vii}
  ]

  @modifier_options [
    {"maj7", :maj7},
    {"dom7 (7)", :dom7},
    {"min7", :min7}
  ]

  @default_chord1_params %{
    "root" => "c",
    "degree" => "I",
    "modifier" => "maj7",
    "octave" => "4"
  }

  @default_chord2_params %{
    "root" => "c",
    "degree" => "V",
    "modifier" => "dom7",
    "octave" => "4"
  }

  @refresh_interval_ms 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:form1, to_form(@default_chord1_params, as: :chord1))
      |> assign(:form2, to_form(@default_chord2_params, as: :chord2))
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:bpm, Mensch.Tempo.bpm())
      |> assign_loop_snapshot(Sequencer.snapshot())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"chord1" => c1, "chord2" => c2}, socket) do
    {:noreply,
     socket
     |> assign(:form1, to_form(c1, as: :chord1))
     |> assign(:form2, to_form(c2, as: :chord2))}
  end

  def handle_event("play", _params, %{assigns: %{loop_status: :playing}} = socket) do
    {:noreply, socket}
  end

  def handle_event("play", %{"chord1" => c1_params, "chord2" => c2_params}, socket) do
    form1 = to_form(c1_params, as: :chord1)
    form2 = to_form(c2_params, as: :chord2)
    socket = socket |> assign(:form1, form1) |> assign(:form2, form2)

    with {:ok, chord1_attrs} <- parse_chord_params(c1_params),
         {:ok, chord2_attrs} <- parse_chord_params(c2_params) do
      Sequencer.play([build_chord(chord1_attrs), build_chord(chord2_attrs)])
      Process.send_after(self(), :refresh_loop, @refresh_interval_ms)

      {:noreply, assign_loop_snapshot(socket, Sequencer.snapshot())}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid chord selection")}
    end
  end

  def handle_event("stop", _params, socket) do
    Sequencer.stop()
    {:noreply, assign_loop_snapshot(socket, Sequencer.snapshot())}
  end

  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  def handle_event("set_bpm", %{"bpm" => bpm_str}, socket) do
    case Integer.parse(bpm_str) do
      {bpm, ""} when bpm > 0 ->
        Mensch.Tempo.set_bpm(bpm)
        {:noreply, assign(socket, :bpm, bpm)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_loop, socket) do
    snapshot = Sequencer.snapshot()
    socket = assign_loop_snapshot(socket, snapshot)

    if snapshot.status == :playing do
      Process.send_after(self(), :refresh_loop, @refresh_interval_ms)
    end

    {:noreply, socket}
  end

  defp assign_loop_snapshot(socket, snapshot) do
    socket
    |> assign(:loop_status, snapshot.status)
    |> assign(:loop_index, snapshot.index)
    |> assign(:loop_bar, snapshot.bar)
    |> assign(:bars_per_step, snapshot.bars_per_step)
    |> assign(:chord_notes, snapshot.notes)
  end

  defp build_chord(%{root: root, degree: degree, modifier: modifier, octave: octave}) do
    key = %Key{root: root, scale: :major}
    Chord.new(key, degree, modifier, octave)
  end

  defp parse_chord_params(params) do
    with root when not is_nil(root) <- find_value(@root_options, params["root"]),
         degree when not is_nil(degree) <- find_value(@degree_options, params["degree"]),
         modifier when not is_nil(modifier) <- find_value(@modifier_options, params["modifier"]),
         {octave, ""} <- Integer.parse(params["octave"] || "") do
      {:ok, %{root: root, degree: degree, modifier: modifier, octave: octave}}
    else
      _ -> :error
    end
  end

  defp find_value(options, string) do
    Enum.find_value(options, fn {_label, value} -> to_string(value) == string && value end)
  end

  defp root_options, do: @root_options
  defp degree_options, do: @degree_options
  defp modifier_options, do: @modifier_options

  defp playing?(loop_status), do: loop_status == :playing

  defp note_label(note, octave) do
    name = Enum.find_value(@root_options, fn {label, value} -> value == note && label end)
    "#{name}#{octave}"
  end

  defp format_bend(bend) do
    percent = Float.round(bend * 100, 3)
    if percent >= 0, do: "+#{percent}%", else: "#{percent}%"
  end

  @input_class "w-full appearance-none rounded-none border-0 border-b border-white/30 bg-black py-2 text-sm uppercase tracking-wide text-white focus:border-white focus:outline-none focus:ring-0 disabled:cursor-not-allowed disabled:opacity-30"

  defp input_class, do: @input_class

  attr :form, :any, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :disabled, :boolean, default: false

  defp chord_fields(assigns) do
    ~H"""
    <div class={[
      "border p-4 transition-colors duration-150",
      (@active && "border-white") || "border-white/15"
    ]}>
      <div class="mb-3 flex items-center gap-2 text-[11px] uppercase tracking-wide text-white/40">
        <span class={[
          "inline-block size-2 rounded-full",
          (@active && "bg-white") || "bg-white/20"
        ]} />
        {@label}
      </div>
      <div class="grid grid-cols-2 gap-x-4 gap-y-2">
        <.input
          field={@form[:root]}
          type="select"
          label="Key"
          options={root_options()}
          class={input_class()}
          disabled={@disabled}
        />
        <.input
          field={@form[:degree]}
          type="select"
          label="Degree"
          options={degree_options()}
          class={input_class()}
          disabled={@disabled}
        />
        <.input
          field={@form[:modifier]}
          type="select"
          label="Quality"
          options={modifier_options()}
          class={input_class()}
          disabled={@disabled}
        />
        <.input
          field={@form[:octave]}
          type="number"
          label="Octave"
          min="0"
          max="8"
          class={input_class()}
          disabled={@disabled}
        />
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} bpm={@bpm}>
      <div class="mx-auto max-w-2xl space-y-8">
        <.form
          for={@form1}
          id="chord-form"
          phx-change="validate"
          phx-submit="play"
          onkeydown="if (event.key === 'Enter' && event.target.tagName === 'INPUT') { event.preventDefault(); }"
        >
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.chord_fields
              form={@form1}
              label="Chord 1"
              active={playing?(@loop_status) and @loop_index == 0}
              disabled={playing?(@loop_status)}
            />
            <.chord_fields
              form={@form2}
              label="Chord 2"
              active={playing?(@loop_status) and @loop_index == 1}
              disabled={playing?(@loop_status)}
            />
          </div>

          <p class="mt-2 text-[11px] uppercase tracking-wide text-white/30">
            Loops Chord 1 → Chord 2 → Chord 1..., 4 bars each, until Stop is pressed
          </p>

          <div class="mt-6 flex gap-3">
            <button
              type="submit"
              id="play-button"
              class="flex-1 border border-white py-3 text-sm font-bold uppercase tracking-widest text-white transition-colors duration-150 hover:bg-white hover:text-black disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-white"
              disabled={playing?(@loop_status)}
            >
              Play
            </button>
            <button
              type="button"
              id="stop-button"
              phx-click="stop"
              class="flex-1 border border-red-500 py-3 text-sm font-bold uppercase tracking-widest text-red-500 transition-colors duration-150 hover:bg-red-500 hover:text-black disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-red-500"
              disabled={!playing?(@loop_status)}
            >
              Stop
            </button>
          </div>
        </.form>

        <div id="loop-position" class="border border-white/15 p-4">
          <div class="flex items-center justify-between text-[11px] uppercase tracking-wide text-white/40">
            <span>Loop position</span>
            <span class="font-mono text-white/70">
              Chord {@loop_index + 1} · Bar {@loop_bar}/{@bars_per_step}
            </span>
          </div>
          <div class="mt-3 grid grid-cols-4 gap-1.5">
            <div
              :for={bar <- 1..@bars_per_step}
              class={[
                "h-2",
                (playing?(@loop_status) && bar == @loop_bar && "bg-white") || "bg-white/15"
              ]}
            />
          </div>
        </div>

        <div :if={@chord_notes != []} id="chord-notes" class="border border-white/15">
          <table class="w-full text-left text-sm">
            <thead>
              <tr class="border-b border-white/15 text-[11px] uppercase tracking-wide text-white/40">
                <th class="px-3 py-2 font-normal">Note</th>
                <th class="px-3 py-2 font-normal">MIDI #</th>
                <th class="px-3 py-2 font-normal">Channel</th>
                <th class="px-3 py-2 font-normal">Pressure</th>
                <th class="px-3 py-2 font-normal">Bend</th>
                <th class="px-3 py-2 font-normal">Slide</th>
              </tr>
            </thead>
            <tbody class="font-mono">
              <tr :for={info <- @chord_notes} class="border-b border-white/10 last:border-0">
                <td class="px-3 py-2 font-medium text-white">
                  {note_label(info.note, info.octave)}
                  <span
                    :if={info.emphasis}
                    class="ml-2 border border-red-500 px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-red-500"
                  >
                    aftertouch
                  </span>
                </td>
                <td class="px-3 py-2 text-white/70">{info.number}</td>
                <td class="px-3 py-2 text-white/70">{info.channel + 1}</td>
                <td class="px-3 py-2 text-white/70">{info.pressure}</td>
                <td class="px-3 py-2 text-white/70">{format_bend(info.bend)}</td>
                <td class="px-3 py-2 text-white/70">{info.slide}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
