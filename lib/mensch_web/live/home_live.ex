defmodule MenschWeb.HomeLive do
  @moduledoc """
  Minimal live-performance UI: pick a key, a scale degree and a chord
  quality, then hold it down with PLAY/STOP while it sounds live on
  the connected MPE MIDI output (e.g. an Osmose).
  """

  use MenschWeb, :live_view

  alias Mensch.Harmony.Key

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

  @default_params %{"root" => "c", "degree" => "I", "modifier" => "maj7", "octave" => "4"}

  @refresh_interval_ms 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:form, to_form(@default_params, as: :chord))
      |> assign(:chord_pid, nil)
      |> assign(:chord_ref, nil)
      |> assign(:chord_notes, [])
      |> assign(:midi_status, Mensch.Midi.Connection.status())

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:chord_pid] do
      pid when is_pid(pid) -> Mensch.ChordSupervisor.stop_chord(pid)
      _ -> :ok
    end

    :ok
  end

  @impl true
  def handle_event("validate", %{"chord" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :chord))}
  end

  def handle_event("play", %{"chord" => params}, %{assigns: %{chord_pid: pid}} = socket)
      when is_pid(pid) do
    {:noreply, assign(socket, :form, to_form(params, as: :chord))}
  end

  def handle_event("play", %{"chord" => params}, socket) do
    form = to_form(params, as: :chord)

    case parse_chord_params(params) do
      {:ok, %{root: root, degree: degree, modifier: modifier, octave: octave}} ->
        key = %Key{root: root, scale: :major}

        case Mensch.ChordSupervisor.start_chord(
               key: key,
               degree: degree,
               modifier: modifier,
               octave: octave
             ) do
          {:ok, pid} ->
            ref = Process.monitor(pid)
            Process.send_after(self(), :refresh_chord, @refresh_interval_ms)

            {:noreply,
             socket
             |> assign(:form, form)
             |> assign(:chord_pid, pid)
             |> assign(:chord_ref, ref)
             |> assign(:chord_notes, Mensch.Chord.snapshot(pid))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:form, form)
             |> put_flash(:error, "Could not start chord: #{inspect(reason)}")}
        end

      :error ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Invalid chord selection")}
    end
  end

  def handle_event("stop", _params, %{assigns: %{chord_pid: pid, chord_ref: ref}} = socket)
      when is_pid(pid) do
    Mensch.ChordSupervisor.stop_chord(pid)
    if ref, do: Process.demonitor(ref, [:flush])

    {:noreply,
     socket |> assign(:chord_pid, nil) |> assign(:chord_ref, nil) |> assign(:chord_notes, [])}
  end

  def handle_event("stop", _params, socket), do: {:noreply, socket}

  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{chord_ref: ref}} = socket
      ) do
    {:noreply,
     socket |> assign(:chord_pid, nil) |> assign(:chord_ref, nil) |> assign(:chord_notes, [])}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  def handle_info(:refresh_chord, %{assigns: %{chord_pid: pid}} = socket) when is_pid(pid) do
    Process.send_after(self(), :refresh_chord, @refresh_interval_ms)
    {:noreply, assign(socket, :chord_notes, Mensch.Chord.snapshot(pid))}
  end

  def handle_info(:refresh_chord, socket), do: {:noreply, socket}

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

  defp playing?(chord_pid), do: is_pid(chord_pid)

  defp midi_status_label({:connected, name}), do: "Connected: #{name}"
  defp midi_status_label(:disconnected), do: "Disconnected"

  defp status_dot_class({:connected, _name}), do: "bg-emerald-400"
  defp status_dot_class(:disconnected), do: "bg-red-500"

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl space-y-8">
        <div class="border-b border-white/15 pb-4">
          <h1 class="text-2xl font-bold uppercase tracking-widest text-white">Play</h1>
          <p class="mt-1 text-xs uppercase tracking-wide text-white/40">
            Live chords over MPE MIDI
          </p>
        </div>

        <div class="flex items-center justify-between border border-white/15 px-4 py-3">
          <span class="flex items-center gap-2 text-xs uppercase tracking-wide text-white/70">
            <span class={["inline-block size-2", status_dot_class(@midi_status)]} />
            <span class="font-mono normal-case tracking-normal">
              {midi_status_label(@midi_status)}
            </span>
          </span>
          <button
            type="button"
            id="reconnect-midi"
            phx-click="reconnect_midi"
            class="border border-white/40 px-3 py-1.5 text-xs font-bold uppercase tracking-widest text-white transition-colors duration-150 hover:bg-white hover:text-black"
          >
            Reconnect
          </button>
        </div>

        <.form for={@form} id="chord-form" phx-change="validate" phx-submit="play">
          <div class="grid grid-cols-2 gap-x-6 gap-y-2 sm:grid-cols-4">
            <.input
              field={@form[:root]}
              type="select"
              label="Key"
              options={root_options()}
              class={input_class()}
              disabled={playing?(@chord_pid)}
            />
            <.input
              field={@form[:degree]}
              type="select"
              label="Degree"
              options={degree_options()}
              class={input_class()}
              disabled={playing?(@chord_pid)}
            />
            <.input
              field={@form[:modifier]}
              type="select"
              label="Quality"
              options={modifier_options()}
              class={input_class()}
              disabled={playing?(@chord_pid)}
            />
            <.input
              field={@form[:octave]}
              type="number"
              label="Octave"
              min="0"
              max="8"
              class={input_class()}
              disabled={playing?(@chord_pid)}
            />
          </div>

          <div class="mt-6 flex gap-3">
            <button
              type="submit"
              id="play-button"
              class="flex-1 border border-white py-3 text-sm font-bold uppercase tracking-widest text-white transition-colors duration-150 hover:bg-white hover:text-black disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-white"
              disabled={playing?(@chord_pid)}
            >
              Play
            </button>
            <button
              type="button"
              id="stop-button"
              phx-click="stop"
              class="flex-1 border border-red-500 py-3 text-sm font-bold uppercase tracking-widest text-red-500 transition-colors duration-150 hover:bg-red-500 hover:text-black disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-red-500"
              disabled={!playing?(@chord_pid)}
            >
              Stop
            </button>
          </div>
        </.form>

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
