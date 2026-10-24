defmodule MenschWeb.ChordLabDiatonicLive do
  use MenschWeb, :live_view

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.DiatonicHarmonicIdentityResolver
  alias Mensch.Harmony.Resolver

  @pitch_classes [
    :c,
    :c_sharp,
    :d,
    :d_sharp,
    :e,
    :f,
    :f_sharp,
    :g,
    :g_sharp,
    :a,
    :a_sharp,
    :b,
    :d_flat,
    :e_flat,
    :g_flat,
    :a_flat,
    :b_flat
  ]

  @modes DiatonicHarmonicIdentityResolver.scale_modes()
  @chord_kinds DiatonicHarmonicIdentityResolver.chord_kinds()

  @pitch_class_from_param Map.new(@pitch_classes, fn pitch_class ->
                            {Atom.to_string(pitch_class), pitch_class}
                          end)

  @mode_from_param Map.new(@modes, fn mode -> {Atom.to_string(mode), mode} end)

  @chord_kind_from_param Map.new(@chord_kinds, fn chord_kind ->
                           {Atom.to_string(chord_kind), chord_kind}
                         end)

  @impl true
  def mount(_params, _session, socket) do
    values = default_values()

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:values, values)
      |> assign(:form, to_form(values, as: :diatonic))
      |> assign(:chord_spec, nil)
      |> assign(:resolved_notes, [])
      |> assign(:preview_note_channels, [])
      |> assign(:preview_stop_ref, nil)
      |> assign(:error_message, nil)
      |> resolve_preview(values)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"diatonic" => params}, socket) do
    values = Map.merge(default_values(), params)
    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_tonic_pitch_class", %{"pitch_class" => tonic}, socket) do
    values =
      if Map.has_key?(@pitch_class_from_param, tonic) do
        Map.put(socket.assigns.values, "tonic", tonic)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    values =
      if Map.has_key?(@mode_from_param, mode) do
        Map.put(socket.assigns.values, "mode", mode)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_chord_kind", %{"chord_kind" => chord_kind}, socket) do
    values =
      if Map.has_key?(@chord_kind_from_param, chord_kind) do
        Map.put(socket.assigns.values, "chord_kind", chord_kind)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_degree", %{"degree" => degree}, socket) do
    values =
      case Integer.parse(to_string(degree)) do
        {parsed_degree, ""} when parsed_degree >= 1 and parsed_degree <= 7 ->
          Map.put(socket.assigns.values, "degree", Integer.to_string(parsed_degree))

        _ ->
          socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_event("play_current_chord", _params, socket) do
    play_notes_for_3s(socket, socket.assigns.resolved_notes)
  end

  @impl true
  def handle_info({:stop_preview_notes, stop_ref}, socket) do
    if socket.assigns.preview_stop_ref == stop_ref do
      {:noreply, stop_preview(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:selected_tonic_keyboard_key, selected_tonic_keyboard_key(assigns.values))
      |> assign(:keyboard_keys, piano_keys(assigns.resolved_notes))
      |> assign(
        :keyboard_degree_labels,
        keyboard_degree_labels(assigns.chord_spec, assigns.resolved_notes)
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:chord_lab_diatonic}>
      <section class="mx-auto w-full max-w-5xl space-y-4">
        <.page_heading
          title="Chord Lab Diatonic"
          subtitle="Generate a diatonic chord spec from tonic, mode, and degree."
        />

        <div class="ui-radius-table border border-zinc-700/60 bg-black/30 p-4">
          <.form for={@form} id="diatonic-builder-form" phx-change="validate" class="space-y-3">
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3">
              <h3 class="mb-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Diatonic Identity
              </h3>
              <div class="space-y-3">
                <MenschWeb.PitchClassKeyboard.mini
                  id="diatonic-tonic-keyboard"
                  label="Tonic"
                  event="set_tonic_pitch_class"
                  selected_key={@selected_tonic_keyboard_key}
                  selected_key_color="#9bf25a"
                />

                <div class="space-y-1">
                  <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Mode
                  </label>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={mode <- modes()}
                      type="button"
                      phx-click="set_mode"
                      phx-value-mode={Atom.to_string(mode)}
                      class={toggle_button_classes(@values["mode"] == Atom.to_string(mode))}
                    >
                      {mode_label(mode)}
                    </button>
                  </div>
                </div>

                <div class="space-y-1">
                  <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Chord Form
                  </label>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={chord_kind <- chord_kinds()}
                      type="button"
                      phx-click="set_chord_kind"
                      phx-value-chord_kind={Atom.to_string(chord_kind)}
                      class={
                        toggle_button_classes(@values["chord_kind"] == Atom.to_string(chord_kind))
                      }
                    >
                      {chord_kind_label(chord_kind)}
                    </button>
                  </div>
                </div>

                <div class="space-y-1">
                  <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Degree
                  </label>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={degree <- 1..7}
                      type="button"
                      phx-click="set_degree"
                      phx-value-degree={degree}
                      class={toggle_button_classes(@values["degree"] == Integer.to_string(degree))}
                    >
                      {degree}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3">
              <h3 class="mb-1 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Render / Playback
              </h3>
              <p class="mb-2 font-mono text-[11px] text-zinc-500">
                These do not change the diatonic identity. They only control how the generated chord is voiced for preview/playback.
              </p>
              <div class="grid gap-3 md:grid-cols-2">
                <.input
                  field={@form[:octave]}
                  type="number"
                  label="Octave"
                  min="-1"
                  max="9"
                  class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                />

                <.input
                  field={@form[:inversion]}
                  type="number"
                  label="Inversion"
                  min="0"
                  max="6"
                  class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                />
              </div>
            </div>
          </.form>

          <div :if={@error_message} class="rounded-sm border border-rose-500/40 bg-rose-950/30 p-3">
            <p class="font-mono text-xs text-rose-200">{@error_message}</p>
          </div>

          <div :if={@chord_spec} class="space-y-3">
            <div class="grid gap-3 md:grid-cols-2">
              <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Chord Symbol
                </h3>
                <p class="mt-1 font-mono text-lg text-zinc-100">
                  {ChordSpec.symbol_label(@chord_spec)}
                </p>
                <p class="mt-1 font-mono text-xs text-cyan-200">
                  Scale: {scale_label(@values)}
                </p>
                <p class="mt-1 font-mono text-xs text-emerald-200">
                  Roman: {roman_numeral(@values, @chord_spec)}
                </p>
                <p class="mt-1 font-mono text-xs text-zinc-400">
                  Root: {ChordSpec.root_label(ChordSpec.root(@chord_spec))} · Quality: {quality_display(
                    @chord_spec
                  )}
                </p>
              </div>

              <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Resolved Notes
                </h3>
                <p class="mt-1 font-mono text-sm text-zinc-200">
                  MIDI: {join_integers(@resolved_notes)}
                </p>
                <p class="mt-1 font-mono text-sm text-zinc-300">
                  Named: {join_named_notes(@resolved_notes)}
                </p>
              </div>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">ChordSpec</h3>
              <pre class="mt-2 overflow-x-auto whitespace-pre-wrap font-mono text-xs text-zinc-100">{inspect(@chord_spec, pretty: true, limit: :infinity)}</pre>
            </div>

            <div class="flex justify-end">
              <button
                type="button"
                phx-click="play_current_chord"
                disabled={@resolved_notes == []}
                class={[
                  "rounded-sm border px-3 py-2 font-mono text-xs font-semibold transition-colors duration-150",
                  @resolved_notes == [] &&
                    "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                  @resolved_notes != [] &&
                    "border-emerald-300 bg-emerald-400/20 text-emerald-100 hover:bg-emerald-400/30"
                ]}
              >
                Play ChordSpec
              </button>
            </div>
          </div>
        </div>

        <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
          <div class="flex items-center justify-between">
            <h2 class="font-mono text-sm text-zinc-200">Final Notes Keyboard</h2>
            <p class="font-mono text-[11px] text-zinc-400">
              Highlighted: {highlighted_count(@resolved_notes)} / 88
            </p>
          </div>

          <div class="relative h-40 rounded-md border border-zinc-700/70 bg-zinc-950">
            <%= for key <- @keyboard_keys do %>
              <div
                :if={key.kind == :white}
                title={key.label}
                class={[
                  "absolute bottom-6 top-0 border-r border-zinc-900 transition-colors duration-150",
                  key.active && "bg-[#9bf25a]",
                  !key.active && "bg-zinc-100"
                ]}
                style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
              >
                <span class={[
                  "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
                  key.active && "text-zinc-900",
                  !key.active && "text-zinc-500"
                ]}>
                  {key.midi}
                </span>
              </div>
            <% end %>

            <%= for key <- @keyboard_keys do %>
              <div
                :if={key.kind == :black}
                title={key.label}
                class={[
                  "absolute top-0 z-10 h-[62%] rounded-b-sm border border-black/70 transition-colors duration-150",
                  key.active && "bg-[#9bf25a]",
                  !key.active && "bg-zinc-900"
                ]}
                style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
              >
                <span class={[
                  "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
                  key.active && "text-zinc-900",
                  !key.active && "text-zinc-300"
                ]}>
                  {key.midi}
                </span>
              </div>
            <% end %>

            <div class="pointer-events-none absolute inset-x-0 bottom-0 h-6">
              <%= for key <- @keyboard_keys do %>
                <span
                  :if={Map.has_key?(@keyboard_degree_labels, key.midi)}
                  class="absolute bottom-1 -translate-x-1/2 font-mono text-[10px] font-semibold text-[#9bf25a]"
                  style={"left: calc(#{key.left_pct}% + #{key.width_pct / 2}%);"}
                >
                  {Map.get(@keyboard_degree_labels, key.midi)}
                </span>
              <% end %>
            </div>
          </div>

          <p class="font-mono text-[11px] text-zinc-400">
            Labels show interval distance from chord root (for example 1, b3, 5, b7).
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp resolve_preview(socket, values) do
    with {:ok, tonic} <- parse_tonic(Map.get(values, "tonic")),
         {:ok, mode} <- parse_mode(Map.get(values, "mode")),
         {:ok, degree} <- parse_degree(Map.get(values, "degree")),
         {:ok, chord_kind} <- parse_chord_kind(Map.get(values, "chord_kind")),
         {:ok, octave} <- parse_integer(Map.get(values, "octave"), "octave"),
         {:ok, inversion} <- parse_integer(Map.get(values, "inversion"), "inversion"),
         {:ok, chord_spec} <-
           DiatonicHarmonicIdentityResolver.build(
             %{tonic: tonic, mode: mode},
             degree,
             chord_kind: chord_kind,
             octave: octave,
             inversion: inversion
           ) do
      resolved_notes = Resolver.resolve(chord_spec)

      socket
      |> assign(:chord_spec, chord_spec)
      |> assign(:resolved_notes, resolved_notes)
      |> assign(:error_message, nil)
    else
      {:error, reason} ->
        socket
        |> assign(:chord_spec, nil)
        |> assign(:resolved_notes, [])
        |> assign(:error_message, format_error(reason))
    end
  rescue
    error in [ArgumentError] ->
      socket
      |> assign(:chord_spec, nil)
      |> assign(:resolved_notes, [])
      |> assign(:error_message, Exception.message(error))
  end

  defp assign_form_values_and_preview(socket, values) do
    socket
    |> assign(:values, values)
    |> assign(:form, to_form(values, as: :diatonic))
    |> resolve_preview(values)
  end

  defp play_notes_for_3s(socket, notes) do
    final_notes = Enum.filter(notes, &is_integer/1)

    cond do
      final_notes == [] ->
        {:noreply, put_flash(socket, :error, "No notes to play")}

      true ->
        socket = stop_preview(socket)

        channels = Mensch.Midi.Connection.member_channels()

        note_channels =
          final_notes
          |> Enum.uniq()
          |> Enum.take(length(channels))
          |> Enum.zip(channels)

        if note_channels == [] do
          {:noreply, put_flash(socket, :error, "No MIDI channels available")}
        else
          on_messages =
            Enum.flat_map(note_channels, fn {note, channel} ->
              [
                <<0x90 + channel, note, 100>>,
                <<0xD0 + channel, 100>>,
                <<0xE0 + channel, 0, 64>>,
                <<0xB0 + channel, 74, 64>>
              ]
            end)

          case Mensch.Midi.Connection.send_messages(on_messages) do
            :ok ->
              stop_ref = make_ref()
              Process.send_after(self(), {:stop_preview_notes, stop_ref}, 3000)

              {:noreply,
               socket
               |> assign(:preview_note_channels, note_channels)
               |> assign(:preview_stop_ref, stop_ref)}

            {:error, :disconnected} ->
              {:noreply, put_flash(socket, :error, "MIDI is disconnected")}
          end
        end
    end
  end

  defp stop_preview(socket) do
    off_messages =
      Enum.flat_map(socket.assigns.preview_note_channels, fn {note, channel} ->
        [
          <<0x80 + channel, note, 0>>,
          <<0x90 + channel, note, 0>>,
          <<0xD0 + channel, 0>>,
          <<0xB0 + channel, 74, 0>>
        ]
      end)

    if off_messages != [] do
      _ = Mensch.Midi.Connection.send_messages(off_messages)
    end

    socket
    |> assign(:preview_note_channels, [])
    |> assign(:preview_stop_ref, nil)
  end

  defp parse_tonic(value) when is_binary(value) do
    case Map.get(@pitch_class_from_param, value) do
      nil -> {:error, "invalid tonic"}
      tonic -> {:ok, tonic}
    end
  end

  defp parse_tonic(_value), do: {:error, "invalid tonic"}

  defp parse_mode(value) when is_binary(value) do
    case Map.get(@mode_from_param, value) do
      nil -> {:error, "invalid mode"}
      mode -> {:ok, mode}
    end
  end

  defp parse_mode(_value), do: {:error, "invalid mode"}

  defp parse_chord_kind(value) when is_binary(value) do
    case Map.get(@chord_kind_from_param, value) do
      nil -> {:error, "invalid chord kind"}
      chord_kind -> {:ok, chord_kind}
    end
  end

  defp parse_chord_kind(_value), do: {:error, "invalid chord kind"}

  defp parse_degree(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 1 and number <= 7 -> {:ok, number}
      _ -> {:error, "degree must be between 1 and 7"}
    end
  end

  defp parse_degree(value) when is_integer(value) and value >= 1 and value <= 7, do: {:ok, value}
  defp parse_degree(_value), do: {:error, "degree must be between 1 and 7"}

  defp parse_integer(value, _field_name) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, field_name) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "#{field_name} must be an integer"}
    end
  end

  defp parse_integer(_value, field_name), do: {:error, "#{field_name} must be an integer"}

  defp format_error({:invalid_tonic, tonic}), do: "Invalid tonic: #{inspect(tonic)}"
  defp format_error({:invalid_mode, mode}), do: "Invalid mode: #{inspect(mode)}"

  defp format_error({:invalid_degree, degree}),
    do: "Invalid degree: #{inspect(degree)} (allowed: 1..7)"

  defp format_error({:invalid_chord_kind, chord_kind}),
    do: "Invalid chord kind: #{inspect(chord_kind)}"

  defp format_error({:missing_opt, key}), do: "Missing required option: #{key}"

  defp format_error({:invalid_opt, key, value}),
    do: "Invalid option #{key}: #{inspect(value)}"

  defp format_error(
         {:unsupported_chord_kind_for_degree,
          %{mode: mode, chord_kind: chord_kind, degree: degree}}
       ),
       do: "#{chord_kind} is not available for degree #{degree} in #{mode}"

  defp format_error(other), do: inspect(other)

  defp quality_display(%ChordSpec{} = spec) do
    quality = ChordSpec.quality(spec)
    Atom.to_string(quality)
  end

  defp join_integers(notes), do: Enum.join(notes, ", ")

  defp join_named_notes(notes) do
    notes
    |> Enum.map(fn note ->
      {name, octave} = ChordSpec.note_name(note)
      "#{ChordSpec.root_label(name)}#{octave}"
    end)
    |> Enum.join("  ")
  end

  defp selected_tonic_keyboard_key(values) do
    case Map.get(values, "tonic", "c") do
      "c_sharp" -> "d_flat"
      "d_sharp" -> "e_flat"
      "f_sharp" -> "g_flat"
      "g_sharp" -> "a_flat"
      "a_sharp" -> "b_flat"
      tonic -> tonic
    end
  end

  defp mode_label(:major), do: "Major"
  defp mode_label(:natural_minor), do: "Natural Minor"
  defp mode_label(:harmonic_minor), do: "Harmonic Minor"

  defp mode_label("major"), do: "Major"
  defp mode_label("natural_minor"), do: "Natural Minor"
  defp mode_label("harmonic_minor"), do: "Harmonic Minor"

  defp chord_kind_label(:triad), do: "Triad"
  defp chord_kind_label(:seventh), do: "Seventh"
  defp chord_kind_label(:add6), do: "Add 6"
  defp chord_kind_label(:six_nine), do: "6/9"
  defp chord_kind_label(:ninth), do: "9th"
  defp chord_kind_label(:eleventh), do: "11th"
  defp chord_kind_label(:thirteenth), do: "13th"

  defp modes, do: @modes
  defp chord_kinds, do: @chord_kinds

  defp scale_label(values) do
    tonic =
      values
      |> Map.get("tonic", "c")
      |> pitch_class_label()

    mode =
      values
      |> Map.get("mode", "major")
      |> mode_label()

    "#{tonic} #{mode}"
  end

  defp pitch_class_label(value) when is_binary(value) do
    case Map.get(@pitch_class_from_param, value) do
      nil -> "C"
      tonic -> ChordSpec.root_label(tonic)
    end
  end

  defp pitch_class_label(_value), do: "C"

  defp roman_numeral(values, %ChordSpec{} = spec) do
    degree = parse_degree_for_display(Map.get(values, "degree", "1"))
    base = Enum.at(["I", "II", "III", "IV", "V", "VI", "VII"], degree - 1, "I")
    quality = ChordSpec.quality(spec)

    cond do
      quality in [:dim, :dim7] ->
        String.downcase(base) <> "°"

      quality == :half_dim ->
        String.downcase(base) <> "ø"

      quality == :aug ->
        base <> "+"

      quality in [:min, :min6, :min7, :min9, :min11, :min7_add11, :min_maj7] ->
        String.downcase(base)

      true ->
        base
    end
  end

  defp parse_degree_for_display(value) when is_integer(value) and value >= 1 and value <= 7,
    do: value

  defp parse_degree_for_display(value) when is_binary(value) do
    case Integer.parse(value) do
      {degree, ""} when degree >= 1 and degree <= 7 -> degree
      _ -> 1
    end
  end

  defp parse_degree_for_display(_value), do: 1

  defp highlighted_count(notes) when is_list(notes) do
    notes
    |> Enum.uniq()
    |> Enum.count(&(&1 >= 21 and &1 <= 108))
  end

  defp highlighted_count(_notes), do: 0

  defp keyboard_degree_labels(nil, _notes), do: %{}
  defp keyboard_degree_labels(_spec, notes) when not is_list(notes), do: %{}

  defp keyboard_degree_labels(%ChordSpec{} = spec, notes) do
    root_semitone =
      spec
      |> ChordSpec.root()
      |> ChordSpec.pitch_class_to_semitone()

    notes
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn midi, acc ->
      distance = rem(rem(midi, 12) - root_semitone + 12, 12)
      Map.put(acc, midi, interval_label(distance))
    end)
  end

  defp interval_label(0), do: "1"
  defp interval_label(1), do: "b2"
  defp interval_label(2), do: "2"
  defp interval_label(3), do: "b3"
  defp interval_label(4), do: "3"
  defp interval_label(5), do: "4"
  defp interval_label(6), do: "b5"
  defp interval_label(7), do: "5"
  defp interval_label(8), do: "#5"
  defp interval_label(9), do: "6"
  defp interval_label(10), do: "b7"
  defp interval_label(11), do: "7"

  defp piano_keys(active_notes) when is_list(active_notes) do
    min_midi = 21
    max_midi = 108

    white_midis = Enum.filter(min_midi..max_midi, &(not black_key?(&1)))
    total_whites = length(white_midis)
    white_width = 100.0 / total_whites
    black_width = white_width * 0.62
    active_set = MapSet.new(active_notes)

    Enum.map(min_midi..max_midi, fn midi ->
      white_before_or_at =
        Enum.count(min_midi..midi, &(not black_key?(&1)))

      if black_key?(midi) do
        %{
          midi: midi,
          kind: :black,
          active: MapSet.member?(active_set, midi),
          left_pct: white_before_or_at * white_width - black_width / 2,
          width_pct: black_width,
          label: note_label(midi)
        }
      else
        left_pct = (white_before_or_at - 1) * white_width

        %{
          midi: midi,
          kind: :white,
          active: MapSet.member?(active_set, midi),
          left_pct: left_pct,
          width_pct: white_width,
          label: note_label(midi)
        }
      end
    end)
  end

  defp piano_keys(_active_notes), do: []

  defp note_label(midi_note) when is_integer(midi_note) do
    {name, octave} = ChordSpec.note_name(midi_note)
    "#{ChordSpec.root_label(name)}#{octave}"
  end

  defp black_key?(midi_note), do: rem(midi_note, 12) in [1, 3, 6, 8, 10]

  defp toggle_button_classes(true) do
    "rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
  end

  defp toggle_button_classes(false) do
    "rounded-sm border border-zinc-700 bg-zinc-900/80 px-3 py-1.5 font-mono text-xs text-zinc-200 transition-colors duration-150 hover:border-zinc-500"
  end

  defp default_values do
    %{
      "tonic" => "c",
      "mode" => "major",
      "degree" => "1",
      "chord_kind" => "triad",
      "octave" => "3",
      "inversion" => "0"
    }
  end
end
