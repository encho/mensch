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

    {:noreply,
     socket
     |> assign(:values, values)
     |> assign(:form, to_form(values, as: :chord))
     |> resolve_preview(values)}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :keyboard_keys,
        piano_keys(
          result_final_notes(assigns.result),
          result_foreign_bass(assigns.result),
          result_resolved_notes(assigns.result),
          result_inverted_notes(assigns.result),
          result_voiced_notes(assigns.result)
        )
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status}>
      <section class="mx-auto w-full max-w-7xl space-y-6">
        <div class="space-y-2">
          <h1 class="font-mono text-2xl text-zinc-100">Chord Lab</h1>
          <p class="font-mono text-xs text-zinc-400">
            Define a chord spec and inspect each step of the new isolated harmony resolver.
          </p>
        </div>

        <div class="grid gap-6 lg:grid-cols-[minmax(320px,420px)_1fr]">
          <div class="ui-radius-table border border-zinc-700/60 bg-black/30 p-4">
            <.form for={@form} id="chord-lab-form" phx-change="validate" class="space-y-2">
              <div class="grid grid-cols-2 gap-2">
                <.input
                  field={@form[:root]}
                  type="select"
                  label="Root"
                  options={pitch_class_options()}
                />
                <.input
                  field={@form[:quality]}
                  type="select"
                  label="Quality"
                  options={quality_options()}
                />
              </div>

              <div class="grid grid-cols-2 gap-2">
                <.input field={@form[:octave]} type="number" min="-1" max="9" label="Octave" />
                <.input field={@form[:inversion]} type="number" min="-24" max="24" label="Inversion" />
              </div>

              <div class="grid grid-cols-2 gap-2">
                <.input
                  field={@form[:voicing_type]}
                  type="select"
                  label="Voicing Type"
                  options={[{"Close", "close"}, {"Open", "open"}]}
                />
                <.input
                  field={@form[:doubling]}
                  type="select"
                  label="Doubling"
                  options={[{"Auto", "auto"}, {"Root", "root"}, {"Top", "top"}]}
                />
              </div>

              <div class="grid grid-cols-3 gap-2">
                <.input
                  field={@form[:center_note]}
                  type="number"
                  min="0"
                  max="127"
                  label="Center Note"
                />
                <.input
                  field={@form[:range_min]}
                  type="number"
                  min="0"
                  max="127"
                  label="Range Min"
                />
                <.input
                  field={@form[:range_max]}
                  type="number"
                  min="0"
                  max="127"
                  label="Range Max"
                />
              </div>

              <div class="grid grid-cols-2 gap-2">
                <.input
                  field={@form[:voice_count]}
                  type="number"
                  min="1"
                  max="12"
                  label="Voice Count"
                />
                <div class="grid grid-cols-2 gap-2">
                  <.input
                    field={@form[:foreign_bass_pitch_class]}
                    type="select"
                    label="Foreign Bass"
                    prompt="none"
                    options={pitch_class_options()}
                  />
                  <.input
                    field={@form[:foreign_bass_octave]}
                    type="number"
                    min="-1"
                    max="9"
                    label="Bass Octave"
                  />
                </div>
              </div>
            </.form>
          </div>

          <div class="space-y-4">
            <div
              :if={@error_message}
              class="ui-radius-btn border border-red-400/60 bg-red-500/10 p-3 font-mono text-xs text-red-100"
            >
              {@error_message}
            </div>

            <div
              :if={@result}
              class="ui-radius-table overflow-hidden border border-zinc-700/60 bg-black/30"
            >
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
          </div>
        </div>

        <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
          <div class="flex items-center justify-between">
            <h2 class="font-mono text-sm text-zinc-200">Final Notes Keyboard</h2>
            <p class="font-mono text-[11px] text-zinc-400">
              Highlighted: {highlighted_count(@result)} / 88
            </p>
          </div>

          <div class="flex items-center gap-4 font-mono text-[11px] text-zinc-300">
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
              <span class="inline-block size-2 rounded-sm bg-[#9bf25a]"></span> Final notes key highlight
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="inline-block size-2 rounded-sm bg-[#6ea83f]"></span> Foreign bass key highlight
            </span>
          </div>

          <div class="w-full overflow-x-auto">
            <div class="relative h-40 min-w-[1320px] rounded-md border border-zinc-700/70 bg-zinc-950">
              <%= for key <- @keyboard_keys do %>
                <div
                  :if={key.kind == :white}
                  title={key.label}
                  class={[
                    "absolute bottom-0 top-0 border-r border-zinc-900 transition-colors duration-150",
                    key.foreign_bass && "bg-[#6ea83f]",
                    !key.foreign_bass && key.active && "bg-[#9bf25a]",
                    !key.active && "bg-zinc-100"
                  ]}
                  style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
                >
                  <span
                    :if={key.resolved_tone}
                    class="pointer-events-none absolute left-[32%] top-1 inline-block size-2 rounded-full bg-[#ff7a1a]"
                  >
                  </span>
                  <span
                    :if={key.inverted_tone}
                    class="pointer-events-none absolute left-[58%] top-1 inline-block size-2 rounded-full bg-[#75b8ff]"
                  >
                  </span>
                  <span
                    :if={key.voiced_tone}
                    class="pointer-events-none absolute left-[76%] top-1 inline-block size-2 rounded-full bg-[#2fd5c8]"
                  >
                  </span>
                  <span
                    :if={key.foreign_bass}
                    class="pointer-events-none absolute left-1/2 top-1 -translate-x-1/2 font-mono text-[11px] font-bold text-zinc-900"
                  >
                    B
                  </span>
                  <span
                    class={[
                      "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
                      key.active && "text-zinc-900",
                      !key.active && "text-zinc-500"
                    ]}
                  >
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
                    key.foreign_bass && "bg-[#6ea83f]",
                    !key.foreign_bass && key.active && "bg-[#9bf25a]",
                    !key.active && "bg-zinc-900"
                  ]}
                  style={"left: #{key.left_pct}%; width: #{key.width_pct}%;"}
                >
                  <span
                    :if={key.resolved_tone}
                    class="pointer-events-none absolute left-[26%] top-1 inline-block size-1.5 rounded-full bg-[#ff7a1a]"
                  >
                  </span>
                  <span
                    :if={key.inverted_tone}
                    class="pointer-events-none absolute left-[58%] top-1 inline-block size-1.5 rounded-full bg-[#75b8ff]"
                  >
                  </span>
                  <span
                    :if={key.voiced_tone}
                    class="pointer-events-none absolute left-[78%] top-1 inline-block size-1.5 rounded-full bg-[#2fd5c8]"
                  >
                  </span>
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
                  <span
                    class={[
                      "pointer-events-none absolute bottom-1 left-1/2 -translate-x-1/2 text-[9px] font-mono",
                      key.active && "text-zinc-900",
                      !key.active && "text-zinc-300"
                    ]}
                  >
                    {key.midi}
                  </span>
                </div>
              <% end %>
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

        socket
        |> assign(:result, result)
        |> assign(:error_message, nil)

      {:error, reason} ->
        socket
        |> assign(:result, nil)
        |> assign(:error_message, reason)
    end
  rescue
    error in [ArgumentError] ->
      socket
      |> assign(:result, nil)
      |> assign(:error_message, Exception.message(error))
  end

  defp parse_spec(values) do
    with {:ok, root} <- parse_pitch_class(values["root"]),
         {:ok, quality} <- parse_quality(values["quality"]),
         {:ok, octave} <- parse_integer(values["octave"], "octave"),
         {:ok, inversion} <- parse_integer(values["inversion"], "inversion"),
         {:ok, voicing_type} <- parse_voicing_type(values["voicing_type"]),
         {:ok, center_note} <- parse_integer(values["center_note"], "center_note"),
         {:ok, range_min} <- parse_optional_integer(values["range_min"], "range_min"),
         {:ok, range_max} <- parse_optional_integer(values["range_max"], "range_max"),
         {:ok, voice_count} <- parse_optional_integer(values["voice_count"], "voice_count"),
         {:ok, doubling} <- parse_doubling(values["doubling"]),
         {:ok, foreign_bass} <-
           parse_foreign_bass(values["foreign_bass_pitch_class"], values["foreign_bass_octave"]) do
      attrs = %{
        root: root,
        quality: quality,
        octave: octave,
        inversion: inversion,
        voicing: %Voicing{
          type: voicing_type,
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

  defp parse_doubling("root"), do: {:ok, :root}
  defp parse_doubling("top"), do: {:ok, :top}
  defp parse_doubling("auto"), do: {:ok, :auto}
  defp parse_doubling(_), do: {:error, "invalid doubling"}

  defp parse_foreign_bass("", _octave), do: {:ok, nil}
  defp parse_foreign_bass(nil, _octave), do: {:ok, nil}

  defp parse_foreign_bass(pitch_class, octave_value) do
    with {:ok, parsed_pitch_class} <- parse_pitch_class(pitch_class),
         {:ok, octave} <- parse_optional_integer(octave_value, "foreign_bass_octave") do
      {:ok, %ForeignBass{pitch_class: parsed_pitch_class, octave: octave}}
    end
  end

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

  defp pitch_class_options do
    @pitch_classes
    |> Enum.map(fn pc ->
      {ChordSpec.root_label(pc), Atom.to_string(pc)}
    end)
  end

  defp quality_options do
    @qualities
    |> Enum.map(fn quality ->
      label =
        quality
        |> Atom.to_string()
        |> String.replace("_", " ")

      {label, Atom.to_string(quality)}
    end)
  end

  defp default_values do
    %{
      "root" => "c",
      "quality" => "maj7",
      "octave" => "3",
      "inversion" => "0",
      "voicing_type" => "close",
      "center_note" => "60",
      "range_min" => "",
      "range_max" => "",
      "voice_count" => "",
      "doubling" => "auto",
      "foreign_bass_pitch_class" => "",
      "foreign_bass_octave" => ""
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

    defp piano_keys(active_notes, foreign_bass_note, resolved_notes, inverted_notes, voiced_notes)
      when is_list(active_notes) and is_list(resolved_notes) and is_list(inverted_notes) and
          is_list(voiced_notes) do
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

  defp show_c_label?(midi_note), do: rem(midi_note, 12) == 0

  defp black_key?(midi_note), do: rem(midi_note, 12) in [1, 3, 6, 8, 10]
end
