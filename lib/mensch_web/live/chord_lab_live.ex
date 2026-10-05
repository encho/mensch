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
end
