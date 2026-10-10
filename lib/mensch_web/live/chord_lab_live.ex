defmodule MenschWeb.ChordLabLive do
  @moduledoc """
  Interactive sandbox for the new isolated harmony engine.

  This page lets you define a chord specification and inspect each resolver step:

  * resolved chord tones
  * inversion result
  * voicing result
  * optional foreign bass
  * final MIDI notes
  """

  use MenschWeb, :live_view

  alias Mensch.ChordSpec, as: LegacyChordSpec
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.ForeignBass
  alias Mensch.Harmony.ChordSpec.Voicing
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

  @qualities [
    :maj,
    :min,
    :maj6,
    :maj7,
    :min7,
    :dom7,
    :sus2,
    :sus4,
    :maj9,
    :min9,
    :dom9,
    :maj11,
    :min11,
    :dom13,
    :six_nine,
    :min6,
    :dim,
    :half_dim,
    :dim7,
    :aug,
    :min7_add11
  ]

  @quality_tiles [
    %{value: "maj", label: "Maj", position: "col-start-1 row-start-1"},
    %{value: "maj6", label: "6", position: "col-start-1 row-start-2"},
    %{value: "maj7", label: "Maj7", position: "col-start-1 row-start-3"},
    %{value: "maj9", label: "Maj9", position: "col-start-1 row-start-4"},
    %{value: "maj11", label: "Maj11", position: "col-start-1 row-start-5"},
    %{value: "six_nine", label: "6/9", position: "col-start-1 row-start-6"},
    %{value: "min", label: "Min", position: "col-start-2 row-start-1"},
    %{value: "min6", label: "Min6", position: "col-start-2 row-start-2"},
    %{value: "min7", label: "Min7", position: "col-start-2 row-start-3"},
    %{value: "min9", label: "Min9", position: "col-start-2 row-start-4"},
    %{value: "min11", label: "Min11", position: "col-start-2 row-start-5"},
    %{value: "min7_add11", label: "m7+11", position: "col-start-2 row-start-6"},
    %{value: "dom7", label: "Dom7", position: "col-start-3 row-start-1"},
    %{value: "dom9", label: "Dom9", position: "col-start-3 row-start-2"},
    %{value: "dom13", label: "Dom13", position: "col-start-3 row-start-3"},
    %{value: "sus2", label: "Sus2", position: "col-start-4 row-start-1"},
    %{value: "sus4", label: "Sus4", position: "col-start-4 row-start-2"},
    %{value: "dim", label: "Dim", position: "col-start-5 row-start-1"},
    %{value: "half_dim", label: "m7b5", position: "col-start-5 row-start-2"},
    %{value: "dim7", label: "Dim7", position: "col-start-5 row-start-3"},
    %{value: "aug", label: "Aug", position: "col-start-5 row-start-4"}
  ]

  @pitch_class_from_param Map.new(@pitch_classes, fn pc -> {Atom.to_string(pc), pc} end)
  @quality_from_param Map.new(@qualities, fn quality -> {Atom.to_string(quality), quality} end)

  @impl true
  def mount(_params, _session, socket) do
    values = default_values()

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:values, values)
      |> assign(:form, to_form(values, as: :chord))
      |> assign(:result, nil)
      |> assign(:error_message, nil)
      |> resolve_preview(values)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"chord" => params}, socket) do
    values = Map.merge(default_values(), params)

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_root_pitch_class", %{"pitch_class" => root}, socket) do
    values =
      if Map.has_key?(@pitch_class_from_param, root) do
        socket.assigns.values
        |> Map.put("root", root)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_foreign_bass_pitch_class", %{"pitch_class" => pitch_class}, socket) do
    values =
      cond do
        pitch_class in ["", nil] ->
          socket.assigns.values
          |> Map.put("foreign_bass_pitch_class", "")

        Map.has_key?(@pitch_class_from_param, pitch_class) ->
          socket.assigns.values
          |> Map.put("foreign_bass_pitch_class", pitch_class)

        true ->
          socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_foreign_bass_mode", %{"mode" => mode}, socket) do
    values =
      if mode in ["absolute", "relative"] do
        socket.assigns.values
        |> Map.put("foreign_bass_mode", mode)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_foreign_bass_octave", %{"foreign_bass_octave" => octave}, socket) do
    values =
      socket.assigns.values
      |> Map.put("foreign_bass_octave", octave)

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_quality", %{"quality" => quality}, socket) do
    values =
      if Map.has_key?(@quality_from_param, quality) do
        socket.assigns.values
        |> Map.put("quality", quality)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_octave", %{"octave" => octave}, socket) do
    values =
      socket.assigns.values
      |> Map.put("octave", octave)

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_inversion_tracking_mode", %{"mode" => mode}, socket) do
    values =
      if mode in ["per_step_centered", "anchor_then_wander"] do
        socket.assigns.values
        |> Map.put("inversion_tracking_mode", mode)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_keyboard_register_controls", params, socket) do
    values =
      socket.assigns.values
      |> Map.put("center_note", Map.get(params, "center_note", socket.assigns.values["center_note"]))
      |> Map.put("range_min", Map.get(params, "range_min", socket.assigns.values["range_min"]))
      |> Map.put("range_max", Map.get(params, "range_max", socket.assigns.values["range_max"]))

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :keyboard_keys,
        piano_keys(
          result_final_notes(assigns.result),
          result_foreign_bass(assigns.result),
          result_resolved_notes(assigns.result),
          result_inverted_notes(assigns.result),
          result_voiced_notes(assigns.result),
          slider_note_value(assigns.values, "center_note", 60),
          keyboard_range_value(assigns.values, "range_min"),
          keyboard_range_value(assigns.values, "range_max")
        )
      )
      |> assign(:selected_root_keyboard_key, selected_root_keyboard_key(assigns.values))
      |> assign(:selected_foreign_bass_keyboard_key, selected_foreign_bass_keyboard_key(assigns.values))

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status}>
      <section class="mx-auto w-full max-w-7xl space-y-6">
        <div class="space-y-2">
          <h1 class="font-mono text-2xl text-zinc-100">Chord Lab</h1>
          <p class="font-mono text-xs text-zinc-400">
            Define a chord spec and inspect each step of the new isolated harmony resolver.
          </p>
        </div>

        <div class="grid gap-4 lg:grid-cols-3">
          <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
            <MenschWeb.PitchClassKeyboard.mini
              id="root-pitch-class-keyboard"
              label="Root"
              event="set_root_pitch_class"
              selected_key={@selected_root_keyboard_key}
            />

            <form phx-change="set_octave" class="space-y-1 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
              <div class="flex items-center justify-between">
                <label for="root-octave-slider" class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Octave
                </label>
                <span class="font-mono text-xs text-zinc-200">{@values["octave"]}</span>
              </div>
              <input
                id="root-octave-slider"
                name="octave"
                type="range"
                min="-1"
                max="9"
                step="1"
                value={@values["octave"]}
                class="w-full accent-emerald-400"
              />
            </form>

            <div class="space-y-2 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
              <MenschWeb.PitchClassKeyboard.mini
                id="foreign-bass-pitch-class-keyboard"
                label="Foreign Bass"
                event="set_foreign_bass_pitch_class"
                selected_key={@selected_foreign_bass_keyboard_key}
                header_action={true}
                header_action_label="No Foreign Bass"
                header_action_value=""
                clear_label="No Foreign Bass"
              />

              <div class="space-y-2">
                <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Bass Placement
                </label>
                <div class="grid grid-cols-2 gap-1">
                  <button
                    type="button"
                    phx-click="set_foreign_bass_mode"
                    phx-value-mode="relative"
                    class={[
                      "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                      @values["foreign_bass_mode"] == "relative" &&
                        "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                      @values["foreign_bass_mode"] != "relative" &&
                        "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                    ]}
                  >
                    Relative
                  </button>
                  <button
                    type="button"
                    phx-click="set_foreign_bass_mode"
                    phx-value-mode="absolute"
                    class={[
                      "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                      @values["foreign_bass_mode"] == "absolute" &&
                        "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                      @values["foreign_bass_mode"] != "absolute" &&
                        "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                    ]}
                  >
                    Absolute
                  </button>
                </div>

                <form phx-change="set_foreign_bass_octave" class="space-y-1">
                  <div class="flex items-center justify-between">
                    <label
                      for="foreign-bass-octave-inline"
                      class="font-mono text-[11px] uppercase tracking-wide text-zinc-400"
                    >
                      Bass Octave
                    </label>
                    <span class="font-mono text-xs text-zinc-200">{@values["foreign_bass_octave"]}</span>
                  </div>
                  <input
                    id="foreign-bass-octave-inline"
                    name="foreign_bass_octave"
                    type="number"
                    min={if @values["foreign_bass_mode"] == "relative", do: "0", else: "-1"}
                    max="9"
                    step="1"
                    value={@values["foreign_bass_octave"]}
                    class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                  />
                </form>
              </div>
            </div>
          </div>

          <div class="ui-radius-table border border-zinc-700/60 bg-black/30 p-4">
            <div class="space-y-1">
              <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Quality</label>
              <div class="rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
                <div class="mb-1 grid grid-cols-5 gap-1">
                  <span class="px-1 font-mono text-[9px] uppercase tracking-wide text-zinc-500">Major</span>
                  <span class="px-1 font-mono text-[9px] uppercase tracking-wide text-zinc-500">Minor</span>
                  <span class="px-1 font-mono text-[9px] uppercase tracking-wide text-zinc-500">Dominant</span>
                  <span class="px-1 font-mono text-[9px] uppercase tracking-wide text-zinc-500">Suspended</span>
                  <span class="px-1 font-mono text-[9px] uppercase tracking-wide text-zinc-500">Dim/Aug</span>
                </div>

                <div class="grid grid-cols-5 grid-rows-6 gap-1">
                  <button
                    :for={tile <- quality_tiles()}
                    type="button"
                    phx-click="set_quality"
                    phx-value-quality={tile.value}
                    class={[
                      "h-9 rounded-md border font-mono text-[10px] font-semibold transition-colors duration-150",
                      tile.position,
                      @values["quality"] == tile.value &&
                        "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                      @values["quality"] != tile.value &&
                        "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                    ]}
                    title={tile.value}
                  >
                    {tile.label}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="ui-radius-table border border-zinc-700/60 bg-black/30 p-4">
            <.form for={@form} id="chord-lab-form" phx-change="validate" class="space-y-2">
              <input type="hidden" name={@form[:root].name} value={@values["root"]} />
              <input type="hidden" name={@form[:quality].name} value={@values["quality"]} />
              <input
                type="hidden"
                name={@form[:foreign_bass_pitch_class].name}
                value={@values["foreign_bass_pitch_class"]}
              />
              <input
                type="hidden"
                name={@form[:foreign_bass_mode].name}
                value={@values["foreign_bass_mode"]}
              />
              <input
                type="hidden"
                name={@form[:foreign_bass_octave].name}
                value={@values["foreign_bass_octave"]}
              />
              <input type="hidden" name={@form[:octave].name} value={@values["octave"]} />
              <input
                type="hidden"
                name={@form[:inversion_tracking_mode].name}
                value={@values["inversion_tracking_mode"]}
              />
              <input
                type="hidden"
                name={@form[:center_note].name}
                value={@values["center_note"]}
              />
              <input
                type="hidden"
                name={@form[:range_min].name}
                value={@values["range_min"]}
              />
              <input
                type="hidden"
                name={@form[:range_max].name}
                value={@values["range_max"]}
              />

              <div class="space-y-2 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
                <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Inversion Control
                </label>

                <div class="space-y-1">
                  <div class="flex items-center justify-between">
                    <label
                      for={@form[:inversion].id}
                      class="font-mono text-[11px] uppercase tracking-wide text-zinc-400"
                    >
                      Inversion
                    </label>
                    <span class="font-mono text-xs text-zinc-200">{@values["inversion"]}</span>
                  </div>
                  <input
                    id={@form[:inversion].id}
                    name={@form[:inversion].name}
                    type="range"
                    min="-24"
                    max="24"
                    step="1"
                    value={@values["inversion"]}
                    class="w-full accent-emerald-400"
                  />
                </div>

                <div class="space-y-1">
                  <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Inversion Tracking
                  </label>
                  <div class="grid grid-cols-2 gap-1">
                    <button
                      type="button"
                      phx-click="set_inversion_tracking_mode"
                      phx-value-mode="per_step_centered"
                      class={[
                        "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                        @values["inversion_tracking_mode"] == "per_step_centered" &&
                          "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                        @values["inversion_tracking_mode"] != "per_step_centered" &&
                          "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                      ]}
                    >
                      Per-step centered
                    </button>
                    <button
                      type="button"
                      phx-click="set_inversion_tracking_mode"
                      phx-value-mode="anchor_then_wander"
                      class={[
                        "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                        @values["inversion_tracking_mode"] == "anchor_then_wander" &&
                          "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                        @values["inversion_tracking_mode"] != "anchor_then_wander" &&
                          "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                      ]}
                    >
                      Anchor then wander
                    </button>
                  </div>
                </div>
              </div>

              <div class="space-y-2 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
                <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Voicing Control
                </label>

                <div class="grid grid-cols-1 gap-2">
                  <.input
                    field={@form[:voicing_type]}
                    type="select"
                    label="Voicing Type"
                    options={[{"Close", "close"}, {"Open", "open"}]}
                  />
                  <.input
                    field={@form[:voice_count]}
                    type="number"
                    min="1"
                    max="12"
                    label="Voice Count"
                  />
                  <.input
                    field={@form[:doubling]}
                    type="select"
                    label="Doubling"
                    options={[{"Auto", "auto"}, {"Root", "root"}, {"Top", "top"}]}
                  />
                </div>
              </div>
            </.form>
          </div>
        </div>

        <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
          <div class="flex items-center justify-between">
            <h2 class="font-mono text-sm text-zinc-200">Final Notes Keyboard</h2>
            <p class="font-mono text-[11px] text-zinc-400">
              Highlighted: {highlighted_count(@result)} / 88
            </p>
          </div>

          <div class="w-full overflow-x-hidden">
            <div class="w-full space-y-3">
              <form phx-change="set_keyboard_register_controls" class="space-y-2">
                <div class="space-y-1.5">
                  <div class="flex items-center justify-between gap-3 font-mono text-[11px] text-zinc-300">
                    <label for="range-min-slider" class="text-zinc-300">Register</label>
                    <div class="grid grid-cols-3 gap-3 text-right">
                      <span>{slider_note_text(@values, "range_min", 21)}</span>
                      <span>{slider_note_text(@values, "center_note", 60)}</span>
                      <span>{slider_note_text(@values, "range_max", 108)}</span>
                    </div>
                  </div>

                  <div class="register-slider-shell relative h-8">
                    <div class="absolute inset-y-0 left-[0.5682%] right-[0.5682%]">
                      <div class="pointer-events-none absolute inset-x-0 top-1/2 h-2 -translate-y-1/2 rounded bg-zinc-700/70"></div>
                      <div
                        class="pointer-events-none absolute top-1/2 h-2 -translate-y-1/2 rounded bg-emerald-300/55"
                        style={
                          "left: #{slider_note_percent(@values, "range_min", 21)}%; width: #{slider_range_width_percent(@values)}%;"
                        }
                      >
                      </div>
                      <div
                        class="pointer-events-none absolute top-1/2 z-10 h-4 w-1.5 -translate-y-1/2 rounded bg-emerald-500"
                        style={"left: calc(#{slider_note_percent(@values, "center_note", 60)}% - 0.1875rem);"}
                      >
                      </div>

                      <input
                        id="range-min-slider"
                        name="range_min"
                        type="range"
                        min="21"
                        max="108"
                        step="1"
                        value={slider_note_value(@values, "range_min", 21)}
                        class="register-range-input register-range-min absolute inset-0"
                      />
                      <input
                        id="center-note-slider"
                        name="center_note"
                        type="range"
                        min="21"
                        max="108"
                        step="1"
                        value={slider_note_value(@values, "center_note", 60)}
                        class="register-range-input register-range-center absolute inset-0"
                      />
                      <input
                        id="range-max-slider"
                        name="range_max"
                        type="range"
                        min="21"
                        max="108"
                        step="1"
                        value={slider_note_value(@values, "range_max", 108)}
                        class="register-range-input register-range-max absolute inset-0"
                      />
                    </div>
                  </div>
                </div>
              </form>

              <div class="relative h-40 rounded-md border border-zinc-700/70 bg-zinc-950">
                <%= for key <- @keyboard_keys do %>
                  <div
                    :if={key.kind == :white}
                    title={key.label}
                    class={[
                      "absolute bottom-0 top-0 border-r border-zinc-900 transition-colors duration-150",
                      key.center_marker && "ring-2 ring-amber-400 ring-inset",
                      key.outside_register && "opacity-35 saturate-50",
                      key.foreign_bass && "bg-[#6ea83f]",
                      !key.foreign_bass && key.active && "bg-[#9bf25a]",
                      !key.active && "bg-zinc-100"
                    ]}
                    style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
                  >
                    <span
                      :if={key.resolved_tone}
                      class="pointer-events-none absolute left-[32%] top-1 inline-block size-2 rounded-full bg-[#ff7a1a]"
                    ></span>
                    <span
                      :if={key.inverted_tone}
                      class="pointer-events-none absolute left-[58%] top-1 inline-block size-2 rounded-full bg-[#75b8ff]"
                    ></span>
                    <span
                      :if={key.voiced_tone}
                      class="pointer-events-none absolute left-[76%] top-1 inline-block size-2 rounded-full bg-[#2fd5c8]"
                    ></span>
                    <span
                      :if={key.foreign_bass}
                      class="pointer-events-none absolute left-1/2 top-1 -translate-x-1/2 font-mono text-[11px] font-bold text-zinc-900"
                    >
                      B
                    </span>
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
                      key.center_marker && "ring-2 ring-amber-400 ring-inset",
                      key.outside_register && "opacity-35 saturate-50",
                      key.foreign_bass && "bg-[#6ea83f]",
                      !key.foreign_bass && key.active && "bg-[#9bf25a]",
                      !key.active && "bg-zinc-900"
                    ]}
                    style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
                  >
                    <span
                      :if={key.resolved_tone}
                      class="pointer-events-none absolute left-[26%] top-1 inline-block size-1.5 rounded-full bg-[#ff7a1a]"
                    ></span>
                    <span
                      :if={key.inverted_tone}
                      class="pointer-events-none absolute left-[58%] top-1 inline-block size-1.5 rounded-full bg-[#75b8ff]"
                    ></span>
                    <span
                      :if={key.voiced_tone}
                      class="pointer-events-none absolute left-[78%] top-1 inline-block size-1.5 rounded-full bg-[#2fd5c8]"
                    ></span>
                    <span
                      :if={key.foreign_bass}
                      class={[
                        "pointer-events-none absolute left-1/2 top-1 -translate-x-1/2 font-mono text-[11px] font-bold",
                        key.active && "text-zinc-900",
                        !key.active && "text-zinc-100"
                      ]}
                    >
                      B
                    </span>
                    <span class={[
                      "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
                      key.active && "text-zinc-900",
                      !key.active && "text-zinc-300"
                    ]}>
                      {key.midi}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-4 font-mono text-[11px] text-zinc-300">
            <span class="inline-flex items-center gap-1.5">
              <span class="inline-block size-2 rounded-full bg-[#ff7a1a]"></span> Resolved chord tones
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="inline-block size-2 rounded-full bg-[#75b8ff]"></span> After inversion
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="inline-block size-2 rounded-full bg-[#2fd5c8]"></span> After voicing
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="inline-block size-2 rounded-sm bg-[#9bf25a]"></span>
              Final notes key highlight
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="inline-block size-2 rounded-sm bg-[#6ea83f]"></span>
              Foreign bass key highlight
            </span>
          </div>
        </div>

        <div class="space-y-4">
          <div
            :if={@error_message}
            class="ui-radius-btn border border-red-400/60 bg-red-500/10 p-3 font-mono text-xs text-red-100"
          >
            {@error_message}
          </div>

          <div
            :if={@result && Map.get(@result, :final_note_details, []) != []}
            class="ui-radius-table overflow-x-auto border border-zinc-700/60 bg-black/30"
          >
            <div class="border-b border-zinc-700/70 px-3 py-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
              Final Note Analysis
            </div>
            <table class="w-full text-left font-mono text-xs text-zinc-200">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-3 py-2 font-normal">MIDI</th>
                  <th class="px-3 py-2 font-normal">Note</th>
                  <th class="px-3 py-2 font-normal">Name</th>
                  <th class="px-3 py-2 font-normal">Oct</th>
                  <th class="px-3 py-2 font-normal">Distance (st)</th>
                  <th class="px-3 py-2 font-normal">Degree</th>
                  <th class="px-3 py-2 font-normal">Compound Preferred</th>
                  <th class="px-3 py-2 font-normal">Interval</th>
                  <th class="px-3 py-2 font-normal">Role</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={detail <- Map.get(@result, :final_note_details, [])}
                  class="border-b border-zinc-700/40 last:border-b-0"
                >
                  <td class="px-3 py-2">{detail.midi_note}</td>
                  <td class="px-3 py-2 text-zinc-100">{detail.named_note_name}</td>
                  <td class="px-3 py-2">{detail.named_note_note}</td>
                  <td class="px-3 py-2">{detail.named_note_octave}</td>
                  <td class="px-3 py-2">{detail.note_distance}</td>
                  <td class="px-3 py-2">{detail.degree_simple}</td>
                  <td class="px-3 py-2">{detail.degree_compound_preferred}</td>
                  <td class="px-3 py-2">{detail.interval_human_label}</td>
                  <td class="px-3 py-2">{detail.chord_tone_role}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="grid gap-4 lg:grid-cols-2">
            <div
              :if={@result}
              class="ui-radius-table overflow-hidden border border-zinc-700/60 bg-black/30"
            >
              <div class="border-b border-zinc-700/70 px-3 py-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Resolution Pipeline
              </div>
              <table class="w-full text-left font-mono text-xs text-zinc-200">
                <thead>
                  <tr class="border-b border-zinc-700/70 text-zinc-400">
                    <th class="px-3 py-2 font-normal">Step</th>
                    <th class="px-3 py-2 font-normal">MIDI Notes</th>
                    <th class="px-3 py-2 font-normal">Named Notes</th>
                  </tr>
                </thead>
                <tbody>
                  <tr class="border-b border-zinc-700/40">
                    <td class="px-3 py-2 text-zinc-300">Resolved chord tones</td>
                    <td class="px-3 py-2">{join_integers(@result.resolved_chord_tones)}</td>
                    <td class="px-3 py-2">{join_named_notes(@result.resolved_chord_tones)}</td>
                  </tr>
                  <tr class="border-b border-zinc-700/40">
                    <td class="px-3 py-2 text-zinc-300">After inversion</td>
                    <td class="px-3 py-2">{join_integers(@result.inverted_chord_tones)}</td>
                    <td class="px-3 py-2">{join_named_notes(@result.inverted_chord_tones)}</td>
                  </tr>
                  <tr class="border-b border-zinc-700/40">
                    <td class="px-3 py-2 text-zinc-300">After voicing</td>
                    <td class="px-3 py-2">{join_integers(@result.voiced_chord_tones)}</td>
                    <td class="px-3 py-2">{join_named_notes(@result.voiced_chord_tones)}</td>
                  </tr>
                  <tr class="border-b border-zinc-700/40">
                    <td class="px-3 py-2 text-zinc-300">Foreign bass</td>
                    <td class="px-3 py-2">{foreign_bass_note_text(@result.foreign_bass_note)}</td>
                    <td class="px-3 py-2">{foreign_bass_named_text(@result.foreign_bass_note)}</td>
                  </tr>
                  <tr>
                    <td class="px-3 py-2 text-zinc-100">Final notes</td>
                    <td class="px-3 py-2 text-zinc-100">{join_integers(@result.final_notes)}</td>
                    <td class="px-3 py-2 text-zinc-100">{join_named_notes(@result.final_notes)}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              :if={@inversion_sequence != []}
              class="ui-radius-table overflow-hidden border border-zinc-700/60 bg-black/30"
            >
              <div class="border-b border-zinc-700/70 px-3 py-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Inversion Sequence
              </div>
              <table class="w-full text-left font-mono text-xs text-zinc-200">
                <thead>
                  <tr class="border-b border-zinc-700/70 text-zinc-400">
                    <th class="px-3 py-2 font-normal">Sequence Inversion</th>
                    <th class="px-3 py-2 font-normal">MIDI Notes</th>
                    <th class="px-3 py-2 font-normal">Named Notes</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={entry <- @inversion_sequence}
                    class={[
                      "border-b border-zinc-700/40 last:border-b-0 transition-colors",
                      entry.inversion == current_inversion(@values) && "bg-emerald-400/12"
                    ]}
                  >
                    <td class={[
                      "px-3 py-2 text-zinc-300",
                      entry.inversion == current_inversion(@values) && "font-semibold text-emerald-200"
                    ]}>
                      {entry.inversion}
                    </td>
                    <td class="px-3 py-2">{join_integers(entry.final_notes)}</td>
                    <td class="px-3 py-2">{join_named_notes(entry.final_notes)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

        </div>

      </section>
    </Layouts.app>
    """
  end

  defp resolve_preview(socket, values) do
    case parse_spec(values) do
      {:ok, spec} ->
        result = Resolver.resolve_steps(spec)
        inversion_sequence = Resolver.resolve_inversion_sequence(spec)

        socket
        |> assign(:result, result)
        |> assign(:inversion_sequence, inversion_sequence)
        |> assign(:error_message, nil)

      {:error, reason} ->
        socket
        |> assign(:result, nil)
        |> assign(:inversion_sequence, [])
        |> assign(:error_message, reason)
    end
  rescue
    error in [ArgumentError] ->
      socket
      |> assign(:result, nil)
      |> assign(:inversion_sequence, [])
      |> assign(:error_message, Exception.message(error))
  end

  defp assign_form_values_and_preview(socket, values) do
    socket
    |> assign(:values, values)
    |> assign(:form, to_form(values, as: :chord))
    |> resolve_preview(values)
  end

  defp quality_tiles, do: @quality_tiles

  defp slider_note_value(values, key, default_value) when is_map(values) and is_binary(key) do
    case Map.get(values, key) do
      nil -> default_value
      "" -> default_value
      value when is_integer(value) -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default_value
        end

      _ -> default_value
    end
  end

  defp slider_note_text(values, key, default_value) do
    note_label(slider_note_value(values, key, default_value))
  end

  defp slider_note_percent(values, key, default_value) do
    note = slider_note_value(values, key, default_value)
    ((note - 21) / 87) * 100
  end

  defp slider_range_width_percent(values) do
    left = slider_note_percent(values, "range_min", 21)
    right = slider_note_percent(values, "range_max", 108)

    max(right - left, 0.5)
  end

  defp selected_root_keyboard_key(values) when is_map(values) do
    root_param = Map.get(values, "root")

    root_param
    |> keyboard_root_from_param()
    |> case do
      nil -> "c"
      root -> root
    end
  end

  defp selected_foreign_bass_keyboard_key(values) when is_map(values) do
    values
    |> Map.get("foreign_bass_pitch_class")
    |> keyboard_root_from_param()
  end

  defp keyboard_root_from_param(root_param) when is_binary(root_param) do
    case Map.get(@pitch_class_from_param, root_param) do
      nil ->
        nil

      pitch_class ->
        pitch_class
        |> ChordSpec.pitch_class_to_semitone()
        |> keyboard_root_from_semitone()
    end
  end

  defp keyboard_root_from_param(_root_param), do: nil

  defp keyboard_root_from_semitone(0), do: "c"
  defp keyboard_root_from_semitone(1), do: "d_flat"
  defp keyboard_root_from_semitone(2), do: "d"
  defp keyboard_root_from_semitone(3), do: "e_flat"
  defp keyboard_root_from_semitone(4), do: "e"
  defp keyboard_root_from_semitone(5), do: "f"
  defp keyboard_root_from_semitone(6), do: "g_flat"
  defp keyboard_root_from_semitone(7), do: "g"
  defp keyboard_root_from_semitone(8), do: "a_flat"
  defp keyboard_root_from_semitone(9), do: "a"
  defp keyboard_root_from_semitone(10), do: "b_flat"
  defp keyboard_root_from_semitone(11), do: "b"
  defp keyboard_root_from_semitone(_), do: nil

  defp parse_spec(values) do
    with {:ok, root} <- parse_pitch_class(values["root"]),
         {:ok, quality} <- parse_quality(values["quality"]),
         {:ok, octave} <- parse_integer(values["octave"], "octave"),
         {:ok, inversion} <- parse_integer(values["inversion"], "inversion"),
         {:ok, voicing_type} <- parse_voicing_type(values["voicing_type"]),
         {:ok, inversion_tracking_mode} <-
           parse_inversion_tracking_mode(values["inversion_tracking_mode"]),
         {:ok, center_note} <- parse_integer(values["center_note"], "center_note"),
         {:ok, range_min} <- parse_optional_integer(values["range_min"], "range_min"),
         {:ok, range_max} <- parse_optional_integer(values["range_max"], "range_max"),
         {:ok, voice_count} <- parse_optional_integer(values["voice_count"], "voice_count"),
         {:ok, doubling} <- parse_doubling(values["doubling"]),
         {:ok, foreign_bass} <-
           parse_foreign_bass(
             values["foreign_bass_pitch_class"],
             values["foreign_bass_mode"],
             values["foreign_bass_octave"]
           ) do
      attrs = %{
        root: root,
        quality: quality,
        octave: octave,
        inversion: inversion,
        voicing: %Voicing{
          type: voicing_type,
          inversion_tracking_mode: inversion_tracking_mode,
          center_note: center_note,
          range_min: range_min,
          range_max: range_max,
          voice_count: voice_count,
          doubling: doubling
        },
        foreign_bass: foreign_bass
      }

      {:ok, ChordSpec.new!(attrs)}
    end
  end

  defp parse_pitch_class(nil), do: {:error, "root is required"}

  defp parse_pitch_class(value) when is_binary(value) do
    case Map.get(@pitch_class_from_param, value) do
      nil -> {:error, "invalid root pitch class"}
      pitch_class -> {:ok, pitch_class}
    end
  end

  defp parse_quality(nil), do: {:error, "quality is required"}

  defp parse_quality(value) when is_binary(value) do
    case Map.get(@quality_from_param, value) do
      nil -> {:error, "invalid quality"}
      quality -> {:ok, quality}
    end
  end

  defp parse_voicing_type("close"), do: {:ok, :close}
  defp parse_voicing_type("open"), do: {:ok, :open}
  defp parse_voicing_type(_), do: {:error, "invalid voicing type"}

  defp parse_inversion_tracking_mode("per_step_centered"), do: {:ok, :per_step_centered}
  defp parse_inversion_tracking_mode("anchor_then_wander"), do: {:ok, :anchor_then_wander}
  defp parse_inversion_tracking_mode(_), do: {:error, "invalid inversion tracking mode"}

  defp parse_doubling("root"), do: {:ok, :root}
  defp parse_doubling("top"), do: {:ok, :top}
  defp parse_doubling("auto"), do: {:ok, :auto}
  defp parse_doubling(_), do: {:error, "invalid doubling"}

  defp parse_foreign_bass("", _mode, _octave), do: {:ok, nil}
  defp parse_foreign_bass(nil, _mode, _octave), do: {:ok, nil}

  defp parse_foreign_bass(pitch_class, mode_value, octave_value) do
    with {:ok, parsed_pitch_class} <- parse_pitch_class(pitch_class),
         {:ok, mode} <- parse_foreign_bass_mode(mode_value),
         {:ok, octave} <- parse_foreign_bass_octave(mode, octave_value) do
      {:ok, %ForeignBass{pitch_class: parsed_pitch_class, mode: mode, octave: octave}}
    end
  end

  defp parse_foreign_bass_mode("relative"), do: {:ok, :relative}
  defp parse_foreign_bass_mode("absolute"), do: {:ok, :absolute}
  defp parse_foreign_bass_mode(_), do: {:error, "foreign_bass_mode is invalid"}

  defp parse_foreign_bass_octave(:relative, value) do
    with {:ok, octave} <- parse_integer(value, "foreign_bass_octave"),
         true <- octave >= 0 do
      {:ok, octave}
    else
      false -> {:error, "foreign_bass_octave must be >= 0 in relative mode"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_foreign_bass_octave(:absolute, value), do: parse_integer(value, "foreign_bass_octave")

  defp parse_integer(value, field_name) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "#{field_name} must be an integer"}
    end
  end

  defp parse_integer(value, _field_name) when is_integer(value), do: {:ok, value}
  defp parse_integer(_value, field_name), do: {:error, "#{field_name} must be an integer"}

  defp parse_optional_integer(nil, _field_name), do: {:ok, nil}
  defp parse_optional_integer("", _field_name), do: {:ok, nil}

  defp parse_optional_integer(value, field_name), do: parse_integer(value, field_name)

  defp current_inversion(%{"inversion" => inversion}) when is_binary(inversion) do
    case Integer.parse(inversion) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp current_inversion(%{"inversion" => inversion}) when is_integer(inversion), do: inversion
  defp current_inversion(_values), do: nil

  defp join_integers(notes), do: Enum.join(notes, ", ")

  defp join_named_notes(notes) do
    notes
    |> Enum.map(fn note ->
      {name, octave} = LegacyChordSpec.note_name(note)
      "#{ChordSpec.root_label(name)}#{octave}"
    end)
    |> Enum.join("  ")
  end

  defp foreign_bass_note_text(nil), do: "-"
  defp foreign_bass_note_text(note), do: Integer.to_string(note)

  defp foreign_bass_named_text(nil), do: "-"

  defp foreign_bass_named_text(note) do
    {name, octave} = LegacyChordSpec.note_name(note)
    "#{ChordSpec.root_label(name)}#{octave}"
  end

  defp default_values do
    %{
      "root" => "c",
      "quality" => "maj7",
      "octave" => "3",
      "inversion" => "0",
      "voicing_type" => "close",
      "inversion_tracking_mode" => "per_step_centered",
      "center_note" => "60",
      "range_min" => "",
      "range_max" => "",
      "voice_count" => "",
      "doubling" => "auto",
      "foreign_bass_mode" => "relative",
      "foreign_bass_pitch_class" => "",
      "foreign_bass_octave" => "0"
    }
  end

  defp result_final_notes(nil), do: []
  defp result_final_notes(result), do: Map.get(result, :final_notes, [])

  defp result_foreign_bass(nil), do: nil
  defp result_foreign_bass(result), do: Map.get(result, :foreign_bass_note)

  defp result_resolved_notes(nil), do: []
  defp result_resolved_notes(result), do: Map.get(result, :resolved_chord_tones, [])

  defp result_inverted_notes(nil), do: []
  defp result_inverted_notes(result), do: Map.get(result, :inverted_chord_tones, [])

  defp result_voiced_notes(nil), do: []
  defp result_voiced_notes(result), do: Map.get(result, :voiced_chord_tones, [])

  defp highlighted_count(nil), do: 0

  defp highlighted_count(result) do
    result
    |> result_final_notes()
    |> Enum.uniq()
    |> Enum.count(&(&1 >= 21 and &1 <= 108))
  end

  defp keyboard_range_value(values, key) when is_map(values) and is_binary(key) do
    case Map.get(values, key) do
      nil -> nil
      "" -> nil
      value when is_integer(value) -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ -> nil
    end
  end

  defp piano_keys(
         active_notes,
         foreign_bass_note,
         resolved_notes,
         inverted_notes,
         voiced_notes,
         center_note,
         range_min,
         range_max
       )
       when is_list(active_notes) and is_list(resolved_notes) and is_list(inverted_notes) and
              is_list(voiced_notes) and is_integer(center_note) and
              (is_nil(range_min) or is_integer(range_min)) and
              (is_nil(range_max) or is_integer(range_max)) do
    min_midi = 21
    max_midi = 108

    white_midis = Enum.filter(min_midi..max_midi, &(not black_key?(&1)))
    total_whites = length(white_midis)
    white_width = 100.0 / total_whites
    black_width = white_width * 0.62
    active_set = MapSet.new(active_notes)
    resolved_set = MapSet.new(resolved_notes)
    inverted_set = MapSet.new(inverted_notes)
    voiced_set = MapSet.new(voiced_notes)

    Enum.map(min_midi..max_midi, fn midi ->
      white_before_or_at =
        Enum.count(min_midi..midi, &(not black_key?(&1)))

      if black_key?(midi) do
        %{
          midi: midi,
          kind: :black,
          active: MapSet.member?(active_set, midi),
          resolved_tone: MapSet.member?(resolved_set, midi),
          inverted_tone: MapSet.member?(inverted_set, midi),
          voiced_tone: MapSet.member?(voiced_set, midi),
          foreign_bass: midi == foreign_bass_note,
          center_marker: midi == center_note,
          outside_register: outside_register?(midi, range_min, range_max),
          left_pct: white_before_or_at * white_width - black_width / 2,
          width_pct: black_width,
          label: note_label(midi),
          show_octave_label: false
        }
      else
        left_pct = (white_before_or_at - 1) * white_width

        %{
          midi: midi,
          kind: :white,
          active: MapSet.member?(active_set, midi),
          resolved_tone: MapSet.member?(resolved_set, midi),
          inverted_tone: MapSet.member?(inverted_set, midi),
          voiced_tone: MapSet.member?(voiced_set, midi),
          foreign_bass: midi == foreign_bass_note,
          center_marker: midi == center_note,
          outside_register: outside_register?(midi, range_min, range_max),
          left_pct: left_pct,
          width_pct: white_width,
          label: note_label(midi),
          show_octave_label: show_c_label?(midi)
        }
      end
    end)
  end

  defp note_label(midi_note) when is_integer(midi_note) do
    {name, octave} = LegacyChordSpec.note_name(midi_note)
    "#{ChordSpec.root_label(name)}#{octave}"
  end

  defp outside_register?(midi_note, range_min, range_max) do
    below_min = is_integer(range_min) and midi_note < range_min
    above_max = is_integer(range_max) and midi_note > range_max
    below_min or above_max
  end

  defp show_c_label?(midi_note), do: rem(midi_note, 12) == 0

  defp black_key?(midi_note), do: rem(midi_note, 12) in [1, 3, 6, 8, 10]
end
