defmodule MenschWeb.ScaleLabLive do
  use MenschWeb, :live_view

  alias Mensch.Scale
  alias Mensch.Scale.ScaleRegistry
  alias Mensch.Scale.ScaleSpec
  alias MenschWeb.FullPianoKeyboard

  @tonics [
    :c,
    :c_sharp,
    :d_flat,
    :d,
    :d_sharp,
    :e_flat,
    :e,
    :f,
    :f_sharp,
    :g_flat,
    :g,
    :g_sharp,
    :a_flat,
    :a,
    :a_sharp,
    :b_flat,
    :b
  ]

  @note_gap_ms 180
  @note_duration_ms 130

  @impl true
  def mount(_params, _session, socket) do
    families = ScaleRegistry.all()
    default_tonic = :c
    default_family = :major
    default_mode = 1

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:families, families)
      |> assign(:selected_tonic, Atom.to_string(default_tonic))
      |> assign(:selected_family, Atom.to_string(default_family))
      |> assign(:selected_mode, Integer.to_string(default_mode))
      |> assign(:scale_spec, nil)
      |> assign(:scale_notes, [])
      |> assign(:scale_pitch_classes, [])
      |> assign(:keyboard_notes, [])
      |> assign(:tonic_keyboard_notes, [])
      |> assign(:preview_notes, [])
      |> assign(:preview_active_notes, [])
      |> assign(:preview_playback_ref, nil)
      |> assign(:error_message, nil)
      |> recompute_scale()

    {:ok, socket}
  end

  @impl true
  def handle_event("set_tonic", %{"pitch_class" => tonic}, socket) do
    selected =
      if tonic in Enum.map(@tonics, &Atom.to_string/1),
        do: tonic,
        else: socket.assigns.selected_tonic

    {:noreply,
     socket
     |> assign(:selected_tonic, selected)
     |> recompute_scale()}
  end

  @impl true
  def handle_event("set_family", params, socket) do
    family = params["family"] || params["family_id"]

    selected =
      if family in Enum.map(socket.assigns.families, &Atom.to_string(&1.id)),
        do: family,
        else: socket.assigns.selected_family

    mode =
      case find_family(socket.assigns.families, selected) do
        %{mode_names: mode_names} when is_map(mode_names) and map_size(mode_names) > 0 -> "1"
        _ -> ""
      end

    {:noreply,
     socket
     |> assign(:selected_family, selected)
     |> assign(:selected_mode, mode)
     |> recompute_scale()}
  end

  @impl true
  def handle_event("set_mode", params, socket) do
    mode = params["mode"] || ""

    {:noreply,
     socket
     |> assign(:selected_mode, mode)
     |> recompute_scale()}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_event("play_scale_notes", _params, socket) do
    play_notes_with_pause(socket, socket.assigns.keyboard_notes)
  end

  @impl true
  def handle_info({:play_preview_note, playback_ref, note}, socket) do
    if socket.assigns.preview_playback_ref == playback_ref do
      on_messages =
        [
          <<0x90, note, 88>>,
          <<0xD0, 90>>,
          <<0xE0, 0, 64>>,
          <<0xB0, 74, 64>>
        ]

      case Mensch.Midi.Connection.send_messages(on_messages) do
        :ok ->
          {:noreply,
           assign(
             socket,
             :preview_active_notes,
             [note | socket.assigns.preview_active_notes] |> Enum.uniq()
           )}

        {:error, :disconnected} ->
          {:noreply,
           socket
           |> stop_preview()
           |> put_flash(:error, "MIDI is disconnected")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stop_preview_note, playback_ref, note}, socket) do
    if socket.assigns.preview_playback_ref == playback_ref do
      off_messages =
        [
          <<0x80, note, 0>>,
          <<0x90, note, 0>>,
          <<0xD0, 0>>,
          <<0xB0, 74, 0>>
        ]

      _ = Mensch.Midi.Connection.send_messages(off_messages)

      {:noreply,
       assign(
         socket,
         :preview_active_notes,
         Enum.reject(socket.assigns.preview_active_notes, &(&1 == note))
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:finish_preview_sequence, playback_ref}, socket) do
    if socket.assigns.preview_playback_ref == playback_ref do
      {:noreply, stop_preview(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :mode_options,
        mode_options(assigns.families, assigns.selected_family, assigns.selected_mode)
      )
      |> assign(:family_options, family_options(assigns.families, assigns.selected_family))
      |> assign(
        :keyboard_keys,
        keyboard_keys(assigns.keyboard_notes, assigns.tonic_keyboard_notes)
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:scale_lab}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Scale Lab"
          subtitle="Explore scales by tonic, family, and mode with full keyboard visualization."
        />

        <div class="ui-radius-table space-y-4 border border-zinc-700/60 bg-black/30 p-4">
          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">Scale Setup</h3>

            <div class="max-w-xl">
              <MenschWeb.PitchClassKeyboard.mini
                id="scale-lab-tonic"
                label="Tonic"
                event="set_tonic"
                selected_key={selected_tonic_keyboard_key(@selected_tonic)}
                selected_key_color="#f6d365"
              />
            </div>

            <div class="grid gap-3 md:grid-cols-2">
              <label class="space-y-1">
                <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Scale Family
                </span>
                <form phx-change="set_family">
                  <select
                    name="family"
                    class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                  >
                    <option :for={item <- @family_options} value={item.value} selected={item.selected}>
                      {item.label}
                    </option>
                  </select>
                </form>
              </label>

              <label class="space-y-1">
                <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Mode
                </span>
                <%= if @mode_options == [] do %>
                  <div class="rounded-sm border border-zinc-800 bg-zinc-950/70 px-2 py-1.5 font-mono text-xs text-zinc-500">
                    No mode (standalone scale)
                  </div>
                <% else %>
                  <form phx-change="set_mode">
                    <select
                      name="mode"
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                    >
                      <option :for={item <- @mode_options} value={item.value} selected={item.selected}>
                        {item.label}
                      </option>
                    </select>
                  </form>
                <% end %>
              </label>
            </div>
          </div>

          <div :if={@error_message} class="rounded-sm border border-rose-500/40 bg-rose-950/30 p-3">
            <p class="font-mono text-xs text-rose-200">{@error_message}</p>
          </div>

          <%= if @scale_spec do %>
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-2">
              <h3 class="font-mono text-sm text-zinc-100">
                {full_scale_name(@selected_tonic, @scale_spec)}
              </h3>
              <p class="font-mono text-xs text-zinc-300">{Enum.join(@scale_notes, "  ")}</p>
              <p class="font-mono text-xs text-zinc-400">
                Intervals: {Enum.join(Enum.map(@scale_spec.intervals, &Integer.to_string/1), " ")}
              </p>
              <p class="font-mono text-xs text-zinc-500">
                Notes: {length(@scale_notes)}
              </p>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-2">
              <div class="flex items-center justify-between">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Piano Keyboard
                </h3>
                <div class="flex items-center gap-3">
                  <p class="font-mono text-[11px] text-zinc-400">
                    Highlighted: {length(@keyboard_notes)} / 88
                  </p>
                  <button
                    type="button"
                    phx-click="play_scale_notes"
                    disabled={@keyboard_notes == []}
                    class={[
                      "rounded-sm border px-3 py-1 font-mono text-[11px] font-semibold transition-colors duration-150",
                      @keyboard_notes == [] &&
                        "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                      @keyboard_notes != [] &&
                        "border-emerald-300 bg-emerald-400/20 text-emerald-100 hover:bg-emerald-400/30"
                    ]}
                  >
                    Play All Notes
                  </button>
                </div>
              </div>

              <FullPianoKeyboard.keyboard
                id="scale-lab-full-keyboard"
                keys={@keyboard_keys}
                height_class="h-40"
                show_bottom_lane={false}
                color_mode={:dark}
              />

              <p class="font-mono text-[11px] text-zinc-400">
                Yellow notes mark tonic across octaves. Green notes are other scale tones.
              </p>
            </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp recompute_scale(socket) do
    with {:ok, tonic} <- parse_tonic(socket.assigns.selected_tonic),
         {:ok, family} <- parse_family(socket.assigns.selected_family),
         {:ok, mode} <-
           parse_mode_for_family(socket.assigns.families, family, socket.assigns.selected_mode),
         {:ok, scale_spec} <- Scale.build_scale(tonic, family, mode),
         {:ok, scale_notes} <- Scale.notes(scale_spec),
         {:ok, scale_pitch_classes} <- Scale.pitch_classes(scale_spec),
         {:ok, keyboard_notes} <- Scale.midi_notes_full_octaves(scale_spec, 21, 108),
         {:ok, tonic_keyboard_notes} <- Scale.tonic_midi_notes(scale_spec, 21, 108) do
      socket
      |> assign(:scale_spec, scale_spec)
      |> assign(:scale_notes, scale_notes)
      |> assign(:scale_pitch_classes, scale_pitch_classes)
      |> assign(:keyboard_notes, keyboard_notes)
      |> assign(:tonic_keyboard_notes, tonic_keyboard_notes)
      |> assign(:error_message, nil)
    else
      {:error, reason} ->
        socket
        |> assign(:scale_spec, nil)
        |> assign(:scale_notes, [])
        |> assign(:scale_pitch_classes, [])
        |> assign(:keyboard_notes, [])
        |> assign(:tonic_keyboard_notes, [])
        |> assign(:error_message, format_error(reason))
    end
  end

  defp parse_tonic(value) when is_binary(value) do
    allowed = MapSet.new(@tonics)

    atom = String.to_atom(value)

    if MapSet.member?(allowed, atom) do
      {:ok, atom}
    else
      {:error, :invalid_tonic}
    end
  end

  defp parse_tonic(_), do: {:error, :invalid_tonic}

  defp parse_family(value) when is_binary(value) do
    case ScaleRegistry.fetch(String.to_atom(value)) do
      {:ok, %{id: id}} -> {:ok, id}
      {:error, _reason} -> {:error, :invalid_family}
    end
  end

  defp parse_family(_), do: {:error, :invalid_family}

  defp parse_mode_for_family(families, family_id, value) do
    case find_family(families, Atom.to_string(family_id)) do
      %{mode_names: mode_names} when is_map(mode_names) and map_size(mode_names) > 0 ->
        case Integer.parse(to_string(value)) do
          {mode, ""} when mode >= 1 -> {:ok, mode}
          _ -> {:ok, 1}
        end

      _ ->
        {:ok, nil}
    end
  end

  defp find_family(families, family_string) do
    Enum.find(families, fn family -> Atom.to_string(family.id) == family_string end)
  end

  defp mode_options(families, selected_family, selected_mode) do
    case find_family(families, selected_family) do
      %{mode_names: mode_names} when is_map(mode_names) and map_size(mode_names) > 0 ->
        mode_names
        |> Enum.sort_by(fn {k, _} -> k end)
        |> Enum.map(fn {index, name} ->
          %{
            value: Integer.to_string(index),
            label: "#{index} — #{name}",
            selected: Integer.to_string(index) == selected_mode
          }
        end)

      _ ->
        []
    end
  end

  defp family_options(families, selected_family) do
    Enum.map(families, fn family ->
      %{
        value: Atom.to_string(family.id),
        label: family.name,
        selected: Atom.to_string(family.id) == selected_family
      }
    end)
  end

  defp keyboard_keys(active_notes, tonic_notes) do
    FullPianoKeyboard.key_maps(
      active_notes: active_notes,
      tonic_notes: tonic_notes
    )
  end

  defp selected_tonic_keyboard_key(tonic) do
    case tonic do
      "c_sharp" -> "d_flat"
      "d_sharp" -> "e_flat"
      "f_sharp" -> "g_flat"
      "g_sharp" -> "a_flat"
      "a_sharp" -> "b_flat"
      other -> other
    end
  end

  defp full_scale_name(tonic, %ScaleSpec{name: name}) do
    "#{tonic_label(tonic)} #{name}"
  end

  defp tonic_label(tonic) when is_binary(tonic) do
    tonic
    |> String.replace("_sharp", "#")
    |> String.replace("_flat", "b")
    |> String.capitalize()
  end

  defp format_error({:invalid_mode_number, mode, size}),
    do: "Invalid mode #{mode}. Allowed range is 1..#{size}."

  defp format_error(reason), do: inspect(reason)

  defp play_notes_with_pause(socket, notes) do
    final_notes =
      notes
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()
      |> Enum.sort()

    octave_notes = full_octave_notes(final_notes, socket.assigns.tonic_keyboard_notes)

    if octave_notes == [] do
      {:noreply, put_flash(socket, :error, "No full-octave tonic range to play")}
    else
      socket = stop_preview(socket)
      playback_ref = make_ref()

      octave_notes
      |> Enum.with_index()
      |> Enum.each(fn {note, idx} ->
        start_at = idx * @note_gap_ms
        Process.send_after(self(), {:play_preview_note, playback_ref, note}, start_at)

        Process.send_after(
          self(),
          {:stop_preview_note, playback_ref, note},
          start_at + @note_duration_ms
        )
      end)

      total_ms =
        max(1, length(octave_notes)) * @note_gap_ms + @note_duration_ms + 20

      Process.send_after(self(), {:finish_preview_sequence, playback_ref}, total_ms)

      {:noreply,
       socket
       |> assign(:preview_notes, octave_notes)
       |> assign(:preview_playback_ref, playback_ref)}
    end
  end

  defp full_octave_notes(notes, tonic_notes) when is_list(notes) and is_list(tonic_notes) do
    tonics =
      tonic_notes
      |> Enum.filter(&is_integer/1)
      |> Enum.sort()

    case tonics do
      [] ->
        []

      [_single] ->
        []

      _ ->
        first_tonic = List.first(tonics)
        last_tonic = List.last(tonics)

        notes
        |> Enum.filter(&(&1 >= first_tonic and &1 <= last_tonic))
        |> Enum.sort()
    end
  end

  defp full_octave_notes(_notes, _tonic_notes), do: []

  defp stop_preview(socket) do
    off_messages =
      Enum.flat_map(socket.assigns.preview_active_notes, fn note ->
        [
          <<0x80, note, 0>>,
          <<0x90, note, 0>>,
          <<0xD0, 0>>,
          <<0xB0, 74, 0>>
        ]
      end)

    if off_messages != [] do
      _ = Mensch.Midi.Connection.send_messages(off_messages)
    end

    socket
    |> assign(:preview_notes, [])
    |> assign(:preview_active_notes, [])
    |> assign(:preview_playback_ref, nil)
  end
end
