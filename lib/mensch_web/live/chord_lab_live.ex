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

  alias Mensch.ChordLists
  alias Mensch.Player
  alias Mensch.Harmony.ChordSpec, as: LegacyChordSpec
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.Parameters
  alias Mensch.Harmony.ChordSpec.ForeignBass
  alias Mensch.Harmony.ChordSpec.Voicing
  alias Mensch.Harmony.Resolver
  alias Mensch.PerformanceAssembler
  alias Mensch.SampleBlueprint

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
    {chord_lists, selected_chord_list_id, selected_chord_list_entries} = load_chord_lists(nil)

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:values, values)
      |> assign(:form, to_form(values, as: :chord))
      |> assign(:result, nil)
      |> assign(:chord_lists, chord_lists)
      |> assign(:selected_chord_list_id, selected_chord_list_id)
      |> assign(:selected_chord_list_entries, selected_chord_list_entries)
      |> assign(:new_chord_list_name, "")
      |> assign(:chord_list_blueprint_settings, default_chord_list_blueprint_settings())
      |> assign(:preview_note_channels, [])
      |> assign(:preview_stop_ref, nil)
      |> assign(:show_doubling_info, false)
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
  def handle_event("set_inversion_resolution_mode", %{"mode" => mode}, socket) do
    values =
      if mode in ["per_step_centered", "anchor_then_wander"] do
        socket.assigns.values
        |> Map.put("inversion_resolution_mode", mode)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_doubling", %{"mode" => mode}, socket) do
    values =
      if mode in doubling_mode_values() and
           not doubling_mode_disabled?(mode, socket.assigns.values) do
        socket.assigns.values
        |> Map.put("doubling", mode)
      else
        socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_voice_count", %{"voice_count" => voice_count}, socket) do
    min_voice_count = minimum_voice_count_from_values(socket.assigns.values)

    values =
      case Integer.parse(to_string(voice_count)) do
        {parsed, ""} ->
          normalized = parsed |> max(min_voice_count) |> min(12)
          Map.put(socket.assigns.values, "voice_count", Integer.to_string(normalized))

        _ ->
          socket.assigns.values
      end

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_voice_count_auto", _params, socket) do
    values = Map.put(socket.assigns.values, "voice_count", "")
    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("set_new_chord_list_name", %{"chord_list" => %{"name" => name}}, socket) do
    {:noreply, assign(socket, :new_chord_list_name, to_string(name))}
  end

  @impl true
  def handle_event("set_chord_list_blueprint_settings", %{"blueprint" => params}, socket) do
    settings =
      socket.assigns.chord_list_blueprint_settings
      |> Map.merge(params)
      |> normalize_chord_list_blueprint_settings()

    {:noreply, assign(socket, :chord_list_blueprint_settings, settings)}
  end

  @impl true
  def handle_event("create_chord_list", %{"chord_list" => %{"name" => name}}, socket) do
    case ChordLists.create_list(name) do
      {:ok, list} ->
        {chord_lists, selected_id, entries} = load_chord_lists(list.id)

        {:noreply,
         socket
         |> assign(:chord_lists, chord_lists)
         |> assign(:selected_chord_list_id, selected_id)
         |> assign(:selected_chord_list_entries, entries)
         |> assign(:new_chord_list_name, "")
         |> put_flash(:info, "Chord list created")}

      {:error, :name_required} ->
        {:noreply, put_flash(socket, :error, "Chord list name is required")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create chord list: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("select_chord_list", %{"list_id" => list_id}, socket) do
    {chord_lists, selected_id, entries} = load_chord_lists(list_id)

    {:noreply,
     socket
     |> assign(:chord_lists, chord_lists)
     |> assign(:selected_chord_list_id, selected_id)
     |> assign(:selected_chord_list_entries, entries)}
  end

  @impl true
  def handle_event("add_current_to_chord_list", _params, socket) do
    case socket.assigns.selected_chord_list_id do
      nil ->
        {:noreply, put_flash(socket, :error, "Select or create a chord list first")}

      list_id ->
        case ChordLists.add_entry(list_id, socket.assigns.values) do
          {:ok, _list} ->
            {chord_lists, selected_id, entries} = load_chord_lists(list_id)

            {:noreply,
             socket
             |> assign(:chord_lists, chord_lists)
             |> assign(:selected_chord_list_id, selected_id)
             |> assign(:selected_chord_list_entries, entries)
             |> put_flash(:info, "Chord added to list")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Could not add chord to list: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("delete_chord_list_entry", %{"entry_id" => entry_id}, socket) do
    case socket.assigns.selected_chord_list_id do
      nil ->
        {:noreply, socket}

      list_id ->
        case ChordLists.delete_entry(list_id, entry_id) do
          {:ok, _list} ->
            {chord_lists, selected_id, entries} = load_chord_lists(list_id)

            {:noreply,
             socket
             |> assign(:chord_lists, chord_lists)
             |> assign(:selected_chord_list_id, selected_id)
             |> assign(:selected_chord_list_entries, entries)}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Could not delete chord entry: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event(
        "move_chord_list_entry",
        %{"entry_id" => entry_id, "direction" => direction},
        socket
      ) do
    case socket.assigns.selected_chord_list_id do
      nil ->
        {:noreply, socket}

      list_id ->
        parsed_direction =
          case direction do
            "up" -> :up
            "down" -> :down
            _ -> nil
          end

        case parsed_direction do
          nil ->
            {:noreply, socket}

          move_direction ->
            case ChordLists.move_entry(list_id, entry_id, move_direction) do
              {:ok, _list} ->
                {chord_lists, selected_id, entries} = load_chord_lists(list_id)

                {:noreply,
                 socket
                 |> assign(:chord_lists, chord_lists)
                 |> assign(:selected_chord_list_id, selected_id)
                 |> assign(:selected_chord_list_entries, entries)}

              {:error, reason} ->
                {:noreply,
                 put_flash(socket, :error, "Could not move chord entry: #{inspect(reason)}")}
            end
        end
    end
  end

  @impl true
  def handle_event("load_chord_list_entry", %{"entry_id" => entry_id}, socket) do
    entry = Enum.find(socket.assigns.selected_chord_list_entries, &(&1.id == entry_id))

    case entry do
      nil ->
        {:noreply, put_flash(socket, :error, "Chord entry not found")}

      _ ->
        values =
          entry
          |> chord_list_entry_values()
          |> Map.merge(default_values(), fn _key, entry_value, _default_value -> entry_value end)

        {:noreply,
         socket
         |> assign_form_values_and_preview(values)
         |> put_flash(:info, "Chord loaded from list")}
    end
  end

  @impl true
  def handle_event("open_doubling_info", _params, socket) do
    {:noreply, assign(socket, :show_doubling_info, true)}
  end

  @impl true
  def handle_event("close_doubling_info", _params, socket) do
    {:noreply, assign(socket, :show_doubling_info, false)}
  end

  @impl true
  def handle_event("set_keyboard_register_controls", params, socket) do
    values =
      socket.assigns.values
      |> Map.put(
        "center_note",
        Map.get(params, "center_note", socket.assigns.values["center_note"])
      )
      |> Map.put("range_min", Map.get(params, "range_min", socket.assigns.values["range_min"]))
      |> Map.put("range_max", Map.get(params, "range_max", socket.assigns.values["range_max"]))

    {:noreply, assign_form_values_and_preview(socket, values)}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_event("play_current_chord", _params, socket) do
    play_notes_for_3s(socket, result_final_notes(socket.assigns.result))
  end

  @impl true
  def handle_event("play_chord_list_entry", %{"entry_id" => entry_id}, socket) do
    entry = Enum.find(socket.assigns.selected_chord_list_entries, &(&1.id == entry_id))

    case entry do
      nil ->
        {:noreply, put_flash(socket, :error, "Chord entry not found")}

      _ ->
        play_notes_for_3s(socket, chord_list_entry_final_notes(entry))
    end
  end

  @impl true
  def handle_event("play_chord_list_blueprint_sample", _params, socket) do
    with {:ok, sample} <- build_sample_from_chord_list(socket),
         :ok <- ensure_sample_entries_not_empty(sample),
         {:ok, performance} <- build_performance_from_sample(sample) do
      socket = stop_preview(socket)
      Player.play(performance)
      {:noreply, put_flash(socket, :info, "Playing chord list blueprint sample")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def handle_event("export_chord_list_blueprint_sample", _params, socket) do
    export_opts = [register: true]

    with {:ok, build_opts} <- chord_list_blueprint_build_opts(socket),
         {:ok, result} <- SampleBlueprint.export_to_sample_db(build_opts, export_opts) do
      {:noreply,
       put_flash(
         socket,
         :info,
         "Exported sample blueprint module #{result.module} to #{result.file}"
       )}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
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
      |> assign(:minimum_voice_count, minimum_voice_count_from_values(assigns.values))
      |> assign(:voice_count_slider_value, voice_count_slider_value(assigns.values))
      |> assign(:keyboard_degree_labels, keyboard_degree_labels(assigns.result))
      |> assign(:selected_root_keyboard_key, selected_root_keyboard_key(assigns.values))
      |> assign(
        :selected_foreign_bass_keyboard_key,
        selected_foreign_bass_keyboard_key(assigns.values)
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:chord_lab}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Chord Lab"
          subtitle="Define a chord spec and inspect each step of the new isolated harmony resolver."
        />

        <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="font-mono text-sm text-zinc-200">Chord Lists</h2>
            <div class="inline-flex items-center gap-2">
              <button
                type="button"
                phx-click="add_current_to_chord_list"
                disabled={is_nil(@selected_chord_list_id) or is_nil(@result)}
                class={[
                  "rounded-sm border px-3 py-1.5 font-mono text-xs font-semibold transition-colors duration-150",
                  (is_nil(@selected_chord_list_id) or is_nil(@result)) &&
                    "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                  (not is_nil(@selected_chord_list_id) and not is_nil(@result)) &&
                    "border-emerald-300 bg-emerald-400/20 text-emerald-100 hover:bg-emerald-400/30"
                ]}
              >
                Add Current Chord
              </button>
              <button
                type="button"
                phx-click="play_chord_list_blueprint_sample"
                disabled={is_nil(@selected_chord_list_id) or @selected_chord_list_entries == []}
                class={[
                  "rounded-sm border px-3 py-1.5 font-mono text-xs font-semibold transition-colors duration-150",
                  (is_nil(@selected_chord_list_id) or @selected_chord_list_entries == []) &&
                    "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                  (not is_nil(@selected_chord_list_id) and @selected_chord_list_entries != []) &&
                    "border-sky-300 bg-sky-400/20 text-sky-100 hover:bg-sky-400/30"
                ]}
              >
                Play List
              </button>
              <button
                type="button"
                phx-click="export_chord_list_blueprint_sample"
                disabled={is_nil(@selected_chord_list_id) or @selected_chord_list_entries == []}
                class={[
                  "rounded-sm border px-3 py-1.5 font-mono text-xs font-semibold transition-colors duration-150",
                  (is_nil(@selected_chord_list_id) or @selected_chord_list_entries == []) &&
                    "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                  (not is_nil(@selected_chord_list_id) and @selected_chord_list_entries != []) &&
                    "border-amber-300 bg-amber-400/20 text-amber-100 hover:bg-amber-400/30"
                ]}
              >
                Export Sample
              </button>
            </div>
          </div>

          <div class="grid gap-3 lg:grid-cols-2">
            <form
              phx-submit="create_chord_list"
              phx-change="set_new_chord_list_name"
              class="space-y-1"
            >
              <label
                for="new-chord-list-name"
                class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400"
              >
                New List
              </label>
              <div class="flex items-center gap-2">
                <input
                  id="new-chord-list-name"
                  name="chord_list[name]"
                  value={@new_chord_list_name}
                  placeholder="e.g. Verse Progression"
                  class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                />
                <button
                  type="submit"
                  class="rounded-sm border border-zinc-700 bg-zinc-900/80 px-3 py-1.5 font-mono text-xs text-zinc-200 hover:border-zinc-500"
                >
                  Create
                </button>
              </div>
            </form>

            <form phx-change="select_chord_list" class="space-y-1">
              <label
                for="selected-chord-list"
                class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400"
              >
                Active List
              </label>
              <select
                id="selected-chord-list"
                name="list_id"
                class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
              >
                <option value="">Select a list</option>
                <option
                  :for={list <- @chord_lists}
                  value={list.id}
                  selected={@selected_chord_list_id == list.id}
                >
                  {list.name} ({list.entry_count})
                </option>
              </select>
            </form>
          </div>

          <div class="rounded-md border border-cyan-600/40 bg-cyan-950/20 p-3">
            <div class="mb-2">
              <h3 class="font-mono text-xs uppercase tracking-wide text-cyan-200">
                Blueprint Configuration
              </h3>
              <p class="font-mono text-[11px] text-cyan-100/80">
                Base sample settings plus blueprint-specific parameters.
              </p>
            </div>

            <form phx-change="set_chord_list_blueprint_settings" class="space-y-3">
              <div class="space-y-2 rounded-md border border-cyan-700/70 bg-cyan-950/25 p-3">
                <h4 class="font-mono text-[11px] uppercase tracking-wide text-cyan-200">Blueprint</h4>
                <label class="space-y-1">
                  <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-300">Type</span>
                  <select
                    name="blueprint[blueprint_id]"
                    value={@chord_list_blueprint_settings["blueprint_id"]}
                    class="w-full rounded-sm border border-cyan-800/70 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                  >
                    <option
                      :for={bp <- sample_blueprint_options()}
                      value={bp.id}
                      selected={@chord_list_blueprint_settings["blueprint_id"] == bp.id}
                    >
                      {bp.label}
                    </option>
                  </select>
                </label>
              </div>

              <div class="space-y-2 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-3">
                <h4 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Base Settings
                </h4>

                <div class="grid gap-2 lg:grid-cols-3">
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">BPM</span>
                    <input
                      name="blueprint[bpm]"
                      type="number"
                      min="1"
                      value={@chord_list_blueprint_settings["bpm"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Chord Duration (mbeats)</span>
                    <input
                      name="blueprint[chord_duration_mbeats]"
                      type="number"
                      min="1"
                      value={@chord_list_blueprint_settings["chord_duration_mbeats"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Silence After Chord (mbeats)</span>
                    <input
                      name="blueprint[silence_after_chord_mbeats]"
                      type="number"
                      min="0"
                      value={@chord_list_blueprint_settings["silence_after_chord_mbeats"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                </div>

                <div class="grid gap-2 lg:grid-cols-4">
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Time Sig Numerator</span>
                    <input
                      name="blueprint[time_signature_numerator]"
                      type="number"
                      min="1"
                      value={@chord_list_blueprint_settings["time_signature_numerator"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Time Sig Denominator</span>
                    <input
                      name="blueprint[time_signature_denominator]"
                      type="number"
                      min="1"
                      value={@chord_list_blueprint_settings["time_signature_denominator"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Sample Name</span>
                    <input
                      name="blueprint[name]"
                      value={@chord_list_blueprint_settings["name"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Folder</span>
                    <input
                      name="blueprint[folder]"
                      value={@chord_list_blueprint_settings["folder"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                </div>

                <div class="grid gap-2 lg:grid-cols-2">
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Optional Sample ID</span>
                    <input
                      name="blueprint[id]"
                      value={@chord_list_blueprint_settings["id"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">Frame mbeats</span>
                    <input
                      name="blueprint[frame_mbeats]"
                      type="number"
                      min="1"
                      value={@chord_list_blueprint_settings["frame_mbeats"]}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </label>
                </div>
              </div>

              <div class="space-y-2 rounded-md border border-cyan-700/70 bg-cyan-950/25 p-3">
                <h4 class="font-mono text-[11px] uppercase tracking-wide text-cyan-200">
                  Blueprint-Specific Settings
                </h4>

                <div
                  :if={blueprint_additional_schema(@chord_list_blueprint_settings) == []}
                  class="font-mono text-xs text-cyan-100/80"
                >
                  No additional settings required for this blueprint.
                </div>

                <div class="grid gap-2 lg:grid-cols-3">
                  <div
                    :for={field <- blueprint_additional_schema(@chord_list_blueprint_settings)}
                    class="space-y-1"
                  >
                    <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                      {field.label}
                    </label>

                    <select
                      :if={field.type == :enum}
                      name={"blueprint[additional][#{field.name}]"}
                      value={blueprint_additional_value(@chord_list_blueprint_settings, field)}
                      class="w-full rounded-sm border border-cyan-800/70 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    >
                      <option
                        :for={option <- Map.get(field, :options, [])}
                        value={option.value}
                        selected={
                          blueprint_additional_value(@chord_list_blueprint_settings, field) ==
                            to_string(option.value)
                        }
                      >
                        {option.label}
                      </option>
                    </select>

                    <input
                      :if={field.type in [:int, :float]}
                      name={"blueprint[additional][#{field.name}]"}
                      type="number"
                      min={Map.get(field, :min)}
                      max={Map.get(field, :max)}
                      step={blueprint_field_input_step(field)}
                      value={blueprint_additional_value(@chord_list_blueprint_settings, field)}
                      class="w-full rounded-sm border border-cyan-800/70 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </div>
                </div>
              </div>
            </form>
          </div>

          <div class="overflow-x-auto rounded-md border border-zinc-700/70">
            <table class="w-full text-left font-mono text-xs text-zinc-200">
              <thead>
                <tr class="border-b border-zinc-700/70 text-zinc-400">
                  <th class="px-3 py-2 font-normal">#</th>
                  <th class="px-3 py-2 font-normal">Chord</th>
                  <th class="px-3 py-2 font-normal">Final Notes</th>
                  <th class="px-3 py-2 font-normal text-right">Action</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{entry, index} <- Enum.with_index(@selected_chord_list_entries, 1)}
                  class="border-b border-zinc-700/40 last:border-b-0"
                >
                  <td class="px-3 py-2 text-zinc-400">{index}</td>
                  <td class="px-3 py-2">{chord_list_entry_label(entry)}</td>
                  <td class="px-3 py-2">{join_integers(chord_list_entry_final_notes(entry))}</td>
                  <td class="px-3 py-2 text-right">
                    <div class="inline-flex items-center gap-1">
                      <button
                        type="button"
                        phx-click="move_chord_list_entry"
                        phx-value-entry_id={entry.id}
                        phx-value-direction="up"
                        disabled={index == 1}
                        class={[
                          "rounded-sm border p-1 transition-colors duration-150",
                          index == 1 &&
                            "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                          index != 1 &&
                            "border-zinc-700 bg-zinc-900/80 text-zinc-300 hover:border-zinc-500"
                        ]}
                        title="Move up"
                        aria-label="Move chord up"
                      >
                        <.icon name="hero-chevron-up" class="size-3" />
                      </button>
                      <button
                        type="button"
                        phx-click="move_chord_list_entry"
                        phx-value-entry_id={entry.id}
                        phx-value-direction="down"
                        disabled={index == length(@selected_chord_list_entries)}
                        class={[
                          "rounded-sm border p-1 transition-colors duration-150",
                          index == length(@selected_chord_list_entries) &&
                            "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                          index != length(@selected_chord_list_entries) &&
                            "border-zinc-700 bg-zinc-900/80 text-zinc-300 hover:border-zinc-500"
                        ]}
                        title="Move down"
                        aria-label="Move chord down"
                      >
                        <.icon name="hero-chevron-down" class="size-3" />
                      </button>
                      <button
                        type="button"
                        phx-click="play_chord_list_entry"
                        phx-value-entry_id={entry.id}
                        disabled={chord_list_entry_final_notes(entry) == []}
                        class={[
                          "rounded-sm border px-2 py-1 font-mono text-[10px] transition-colors duration-150",
                          chord_list_entry_final_notes(entry) == [] &&
                            "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                          chord_list_entry_final_notes(entry) != [] &&
                            "border-emerald-300 bg-emerald-400/20 text-emerald-100 hover:bg-emerald-400/30"
                        ]}
                      >
                        Play
                      </button>
                      <button
                        type="button"
                        phx-click="load_chord_list_entry"
                        phx-value-entry_id={entry.id}
                        class="rounded-sm border border-emerald-400/70 bg-emerald-500/15 px-2 py-1 font-mono text-[10px] text-emerald-100 hover:bg-emerald-500/25"
                      >
                        Load
                      </button>
                      <button
                        type="button"
                        phx-click="delete_chord_list_entry"
                        phx-value-entry_id={entry.id}
                        class="rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-[10px] text-zinc-300 hover:border-zinc-500"
                      >
                        Remove
                      </button>
                    </div>
                  </td>
                </tr>
                <tr :if={@selected_chord_list_entries == []}>
                  <td colspan="4" class="px-3 py-3 text-center text-zinc-500">
                    No chords in this list yet.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="grid gap-4 lg:grid-cols-3">
          <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
            <div class="space-y-2 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-3">
              <div class="flex items-center justify-between">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Harmonic Identity
                </h3>
                <div class="grid grid-cols-2 gap-1">
                  <button
                    type="button"
                    class="rounded-sm border border-emerald-300 bg-emerald-400/25 px-2 py-1 font-mono text-[10px] font-semibold text-emerald-100"
                  >
                    Manual
                  </button>
                  <button
                    type="button"
                    disabled
                    class="cursor-not-allowed rounded-sm border border-zinc-800 bg-zinc-950/70 px-2 py-1 font-mono text-[10px] font-semibold text-zinc-600 opacity-60"
                    title="Diatonic identity resolver input is coming next"
                  >
                    Diatonic
                  </button>
                </div>
              </div>
              <p class="font-mono text-[11px] text-zinc-300">
                {identity_summary(@values)}
              </p>
            </div>

            <MenschWeb.PitchClassKeyboard.mini
              id="root-pitch-class-keyboard"
              label="Root"
              event="set_root_pitch_class"
              selected_key={@selected_root_keyboard_key}
              selected_key_color="#9bf25a"
            />

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
            <div class="space-y-2 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
              <MenschWeb.PitchClassKeyboard.mini
                id="foreign-bass-pitch-class-keyboard"
                label="Foreign Bass"
                event="set_foreign_bass_pitch_class"
                selected_key={@selected_foreign_bass_keyboard_key}
                selected_key_color="#ff4d6d"
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
              <input
                type="hidden"
                name={@form[:inversion_resolution_mode].name}
                value={@values["inversion_resolution_mode"]}
              />
              <input type="hidden" name={@form[:doubling].name} value={@values["doubling"]} />
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
              <input type="hidden" name={@form[:voice_count].name} value={@values["voice_count"]} />

              <div class="space-y-1 rounded-md border border-zinc-700/70 bg-zinc-950/60 p-2">
                <div class="flex items-center justify-between">
                  <label
                    for="root-octave-slider"
                    class="font-mono text-[11px] uppercase tracking-wide text-zinc-400"
                  >
                    Octave
                  </label>
                  <span class="font-mono text-xs text-zinc-200">{@values["octave"]}</span>
                </div>
                <input
                  id="root-octave-slider"
                  name={@form[:octave].name}
                  type="range"
                  min="-1"
                  max="9"
                  step="1"
                  value={@values["octave"]}
                  class="w-full accent-emerald-400"
                />
              </div>

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
                      phx-click="set_inversion_resolution_mode"
                      phx-value-mode="per_step_centered"
                      class={[
                        "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                        @values["inversion_resolution_mode"] == "per_step_centered" &&
                          "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                        @values["inversion_resolution_mode"] != "per_step_centered" &&
                          "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                      ]}
                    >
                      Per-step centered
                    </button>
                    <button
                      type="button"
                      phx-click="set_inversion_resolution_mode"
                      phx-value-mode="anchor_then_wander"
                      class={[
                        "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                        @values["inversion_resolution_mode"] == "anchor_then_wander" &&
                          "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                        @values["inversion_resolution_mode"] != "anchor_then_wander" &&
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
                  <div class="space-y-1 rounded-sm border border-zinc-700/70 bg-zinc-900/50 p-2">
                    <div class="flex items-center justify-between">
                      <label
                        for="voice-count-slider"
                        class="font-mono text-[11px] uppercase tracking-wide text-zinc-400"
                      >
                        Voice Count
                      </label>
                      <span class="font-mono text-xs text-zinc-200">
                        {if @values["voice_count"] in [nil, ""],
                          do: "Auto (min #{@minimum_voice_count})",
                          else: @values["voice_count"]}
                      </span>
                    </div>
                    <input
                      id="voice-count-slider"
                      name="voice_count"
                      type="range"
                      min={@minimum_voice_count}
                      max="12"
                      step="1"
                      value={@voice_count_slider_value}
                      phx-change="set_voice_count"
                      class="w-full accent-emerald-400"
                    />
                    <div class="flex items-center justify-between">
                      <p class="font-mono text-[10px] text-zinc-500">
                        Minimum: {@minimum_voice_count}
                      </p>
                      <button
                        type="button"
                        phx-click="set_voice_count_auto"
                        class={[
                          "rounded-sm border px-2 py-1 font-mono text-[10px] transition-colors duration-150",
                          @values["voice_count"] in [nil, ""] &&
                            "border-emerald-300 bg-emerald-400/20 text-emerald-100",
                          @values["voice_count"] not in [nil, ""] &&
                            "border-zinc-700 bg-zinc-900/80 text-zinc-300 hover:border-zinc-500"
                        ]}
                      >
                        Auto/Min
                      </button>
                    </div>
                  </div>
                  <div class="space-y-1">
                    <div class="flex items-center justify-between">
                      <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                        Doubling
                      </label>
                      <button
                        type="button"
                        phx-click="open_doubling_info"
                        class="inline-flex size-5 items-center justify-center rounded-full border border-zinc-600 bg-zinc-900/80 font-mono text-[11px] font-bold leading-none text-zinc-200 transition-colors duration-150 hover:border-zinc-400 hover:text-white"
                        title="Show doubling strategy information"
                        aria-label="Show doubling strategy information"
                      >
                        i
                      </button>
                    </div>
                    <div class="grid grid-cols-2 gap-1">
                      <button
                        :for={mode <- doubling_modes()}
                        type="button"
                        phx-click="set_doubling"
                        phx-value-mode={mode.value}
                        disabled={doubling_mode_disabled?(mode.value, @values)}
                        class={[
                          "rounded-sm border px-2 py-1 font-mono text-[10px] font-semibold transition-colors duration-150",
                          doubling_mode_disabled?(mode.value, @values) &&
                            "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                          not doubling_mode_disabled?(mode.value, @values) &&
                            @values["doubling"] == mode.value &&
                            "border-emerald-300 bg-emerald-400/25 text-emerald-100",
                          not doubling_mode_disabled?(mode.value, @values) &&
                            @values["doubling"] != mode.value &&
                            "border-zinc-700 bg-zinc-900/80 text-zinc-200 hover:border-zinc-500"
                        ]}
                        title={mode.description}
                      >
                        {mode.label}
                      </button>
                    </div>
                  </div>
                  <p class="font-mono text-[10px] text-zinc-500">
                    Doubling is used only when Voice Count is greater than the chord tone count.
                  </p>
                </div>
              </div>
            </.form>
          </div>
        </div>

        <div class="ui-radius-table space-y-3 border border-zinc-700/60 bg-black/30 p-4">
          <div class="flex items-center justify-between">
            <h2 class="font-mono text-sm text-zinc-200">Final Notes Keyboard</h2>
            <div class="flex items-center gap-3">
              <p class="font-mono text-[11px] text-zinc-400">
                Highlighted: {highlighted_count(@result)} / 88
              </p>
              <button
                type="button"
                phx-click="play_current_chord"
                disabled={result_final_notes(@result) == []}
                class={[
                  "rounded-sm border px-3 py-1 font-mono text-[11px] font-semibold transition-colors duration-150",
                  result_final_notes(@result) == [] &&
                    "cursor-not-allowed border-zinc-800 bg-zinc-950/70 text-zinc-600 opacity-50",
                  result_final_notes(@result) != [] &&
                    "border-emerald-300 bg-emerald-400/20 text-emerald-100 hover:bg-emerald-400/30"
                ]}
              >
                Play 3s
              </button>
            </div>
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
                      <div class="pointer-events-none absolute inset-x-0 top-1/2 h-2 -translate-y-1/2 rounded bg-zinc-700/70">
                      </div>
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
                      "absolute bottom-6 top-0 border-r border-zinc-900 transition-colors duration-150",
                      key.center_marker && "ring-2 ring-amber-400 ring-inset",
                      key.outside_register && "opacity-35 saturate-50",
                      key.foreign_bass && "bg-[#ff4d6d]",
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
                      key.foreign_bass && "bg-[#ff4d6d]",
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
                      :if={Map.has_key?(@keyboard_degree_labels, key.midi) or key.foreign_bass}
                      class={[
                        "absolute bottom-1 -translate-x-1/2 font-mono text-[10px] font-semibold",
                        key.foreign_bass && "text-[#ff4d6d]",
                        !key.foreign_bass && "text-[#9bf25a]",
                        key.outside_register && "opacity-45"
                      ]}
                      style={"left: calc(#{key.left_pct}% + #{key.width_pct / 2}%);"}
                    >
                      {if key.foreign_bass, do: "B", else: Map.get(@keyboard_degree_labels, key.midi)}
                    </span>
                  <% end %>
                </div>
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
              <span class="inline-block size-2 rounded-sm bg-[#ff4d6d]"></span>
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
                      entry.inversion == current_inversion(@values) &&
                        "font-semibold text-emerald-200"
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

        <div
          :if={@show_doubling_info}
          class="fixed inset-0 z-50 flex items-center justify-center px-4"
        >
          <button
            type="button"
            phx-click="close_doubling_info"
            class="absolute inset-0 bg-black/70"
            aria-label="Close doubling information"
          ></button>
          <div
            class="ui-radius-table relative z-10 w-full max-w-2xl border border-zinc-600 bg-zinc-950/95 p-4 shadow-2xl"
            phx-click-away="close_doubling_info"
          >
            <div class="mb-3 flex items-start justify-between gap-3">
              <div>
                <h3 class="font-mono text-sm text-zinc-100">Doubling Strategies</h3>
                <p class="mt-1 font-mono text-[11px] text-zinc-400">
                  Applied only when Voice Count exceeds the number of chord tones.
                </p>
              </div>
              <button
                type="button"
                phx-click="close_doubling_info"
                class="inline-flex size-7 items-center justify-center rounded-full border border-zinc-600 bg-zinc-900/80 text-zinc-200 transition-colors duration-150 hover:border-zinc-400 hover:text-white"
                aria-label="Close doubling information"
                title="Close"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div class="overflow-x-auto rounded-md border border-zinc-700/70">
              <table class="w-full text-left font-mono text-xs text-zinc-200">
                <thead>
                  <tr class="border-b border-zinc-700/70 text-zinc-400">
                    <th class="px-3 py-2 font-normal">Mode</th>
                    <th class="px-3 py-2 font-normal">What Gets Doubled</th>
                    <th class="px-3 py-2 font-normal">Availability</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={row <- doubling_info_rows()}
                    class="border-b border-zinc-700/40 last:border-b-0"
                  >
                    <td class="px-3 py-2 text-zinc-100">{row.label}</td>
                    <td class="px-3 py-2">{row.explanation}</td>
                    <td class="px-3 py-2 text-zinc-300">{row.availability}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <p class="mt-3 font-mono text-[11px] text-zinc-500">
              Tip: use Guide or Third when you want stronger functional identity; use Bass for heavier low-end emphasis.
            </p>
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
    values = normalize_voice_count_value(values)

    socket
    |> assign(:values, values)
    |> assign(:form, to_form(values, as: :chord))
    |> resolve_preview(values)
  end

  defp minimum_voice_count_from_values(values) when is_map(values) do
    case Map.get(values, "quality") do
      quality when is_binary(quality) ->
        case Map.get(@quality_from_param, quality) do
          nil -> 1
          quality_atom -> ChordSpec.min_voice_count_for_quality(quality_atom)
        end

      _ ->
        1
    end
  end

  defp voice_count_slider_value(values) do
    min_voice_count = minimum_voice_count_from_values(values)

    values
    |> Map.get("voice_count")
    |> parse_integer_or_nil()
    |> case do
      nil -> min_voice_count
      count -> count |> max(min_voice_count) |> min(12)
    end
  end

  defp normalize_voice_count_value(values) do
    min_voice_count = minimum_voice_count_from_values(values)

    values
    |> Map.get("voice_count")
    |> parse_integer_or_nil()
    |> case do
      nil ->
        values

      count when count < min_voice_count ->
        Map.put(values, "voice_count", Integer.to_string(min_voice_count))

      count when count > 12 ->
        Map.put(values, "voice_count", "12")

      _ ->
        values
    end
  end

  defp parse_integer_or_nil(nil), do: nil
  defp parse_integer_or_nil(""), do: nil
  defp parse_integer_or_nil(value) when is_integer(value), do: value

  defp parse_integer_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer_or_nil(_value), do: nil

  defp quality_tiles, do: @quality_tiles

  defp identity_summary(values) when is_map(values) do
    root_label =
      case parse_pitch_class(Map.get(values, "root")) do
        {:ok, root} -> ChordSpec.root_label(root)
        _ -> "?"
      end

    quality = Map.get(values, "quality", "?")
    symbol = "#{root_label}#{quality}"
    "#{symbol} | Root #{root_label} | Quality #{quality}"
  end

  defp identity_summary(_values), do: "? | Root ? | Quality ?"

  defp slider_note_value(values, key, default_value) when is_map(values) and is_binary(key) do
    case Map.get(values, key) do
      nil ->
        default_value

      "" ->
        default_value

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default_value
        end

      _ ->
        default_value
    end
  end

  defp slider_note_text(values, key, default_value) do
    note_label(slider_note_value(values, key, default_value))
  end

  defp slider_note_percent(values, key, default_value) do
    note = slider_note_value(values, key, default_value)
    (note - 21) / 87 * 100
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
         {:ok, inversion_resolution_mode} <-
           parse_inversion_resolution_mode(values["inversion_resolution_mode"]),
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
        harmonic_identity: %Mensch.Harmony.ChordSpec.HarmonicIdentity{
          root: root,
          quality: quality
        },
        octave: octave,
        inversion: inversion,
        voicing: %Voicing{
          type: voicing_type,
          inversion_resolution_mode: inversion_resolution_mode,
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

  defp parse_inversion_resolution_mode("per_step_centered"), do: {:ok, :per_step_centered}
  defp parse_inversion_resolution_mode("anchor_then_wander"), do: {:ok, :anchor_then_wander}
  defp parse_inversion_resolution_mode(_), do: {:error, "invalid inversion resolution mode"}

  defp parse_doubling("root"), do: {:ok, :root}
  defp parse_doubling("top"), do: {:ok, :top}
  defp parse_doubling("auto"), do: {:ok, :auto}
  defp parse_doubling("third"), do: {:ok, :third}
  defp parse_doubling("fifth"), do: {:ok, :fifth}
  defp parse_doubling("guide_tones"), do: {:ok, :guide_tones}
  defp parse_doubling("bass"), do: {:ok, :bass}
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

  defp parse_foreign_bass_octave(:absolute, value),
    do: parse_integer(value, "foreign_bass_octave")

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
      "inversion_resolution_mode" => "per_step_centered",
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

  defp default_chord_list_blueprint_settings do
    settings = %{
      "blueprint_id" => SampleBlueprint.default_blueprint_id(),
      "bpm" => "120",
      "time_signature_numerator" => "4",
      "time_signature_denominator" => "4",
      "chord_duration_mbeats" => "4000",
      "silence_after_chord_mbeats" => "0",
      "name" => "Chord List Generated Sample",
      "folder" => "Generated",
      "id" => "",
      "frame_mbeats" => "50"
    }

    normalize_chord_list_blueprint_settings(settings)
  end

  defp sample_blueprint_options do
    SampleBlueprint.available_blueprints()
  end

  defp blueprint_additional_schema(settings) do
    blueprint_id = Map.get(settings, "blueprint_id", SampleBlueprint.default_blueprint_id())

    case SampleBlueprint.additional_param_schema(blueprint_id) do
      {:ok, schema} -> schema
      {:error, _} -> []
    end
  end

  defp blueprint_additional_value(settings, field) do
    additional = Map.get(settings, "additional", %{})
    value = Map.get(additional, field.name, field.default)
    to_string(value)
  end

  defp blueprint_field_input_step(%{type: :int}), do: "1"

  defp blueprint_field_input_step(%{type: :float} = field),
    do: to_string(Map.get(field, :step, 0.1))

  defp normalize_chord_list_blueprint_settings(settings) when is_map(settings) do
    defaults = %{
      "blueprint_id" => SampleBlueprint.default_blueprint_id(),
      "bpm" => "120",
      "time_signature_numerator" => "4",
      "time_signature_denominator" => "4",
      "chord_duration_mbeats" => "4000",
      "silence_after_chord_mbeats" => "0",
      "name" => "Chord List Generated Sample",
      "folder" => "Generated",
      "id" => "",
      "frame_mbeats" => "50",
      "additional" => %{}
    }

    merged = Map.merge(defaults, settings)
    blueprint_id = Map.get(merged, "blueprint_id", SampleBlueprint.default_blueprint_id())

    with {:ok, schema} <- SampleBlueprint.additional_param_schema(blueprint_id),
         {:ok, default_additional} <- SampleBlueprint.default_additional_params(blueprint_id) do
      incoming_additional =
        merged
        |> Map.get("additional", %{})
        |> normalize_map_string_keys()

      allowed_keys = Enum.map(schema, & &1.name)

      normalized_additional =
        default_additional
        |> normalize_map_string_keys()
        |> Map.merge(incoming_additional)
        |> Map.take(allowed_keys)

      Map.put(merged, "additional", normalized_additional)
    else
      _ ->
        Map.put(merged, "additional", %{})
    end
  end

  defp chord_list_blueprint_build_opts(socket) do
    entries = socket.assigns.selected_chord_list_entries || []

    if entries == [] do
      {:error, "Selected chord list is empty"}
    else
      settings =
        default_chord_list_blueprint_settings()
        |> Map.merge(socket.assigns.chord_list_blueprint_settings || %{})

      normalized_settings = normalize_chord_list_blueprint_settings(settings)

      chords = Enum.map(entries, &Map.fetch!(&1, :parameters))

      {:ok,
       %{
         id: Map.get(normalized_settings, "id"),
         folder: Map.get(normalized_settings, "folder"),
         name: Map.get(normalized_settings, "name"),
         blueprint_id: Map.get(normalized_settings, "blueprint_id"),
         bpm: Map.get(normalized_settings, "bpm"),
         time_signature: %{
           "numerator" => Map.get(normalized_settings, "time_signature_numerator"),
           "denominator" => Map.get(normalized_settings, "time_signature_denominator")
         },
         frame_mbeats: Map.get(normalized_settings, "frame_mbeats"),
         chord_duration_mbeats: Map.get(normalized_settings, "chord_duration_mbeats"),
         silence_after_chord_mbeats: Map.get(normalized_settings, "silence_after_chord_mbeats"),
         blueprint_additional_params: Map.get(normalized_settings, "additional", %{}),
         chords: chords
       }}
    end
  end

  defp build_sample_from_chord_list(socket) do
    with {:ok, build_opts} <- chord_list_blueprint_build_opts(socket),
         {:ok, sample} <- SampleBlueprint.build(build_opts) do
      {:ok, sample}
    end
  end

  defp ensure_sample_entries_not_empty(%{sample_entries: entries}) when is_list(entries) do
    if entries == [], do: {:error, "Generated sample has no entries"}, else: :ok
  end

  defp build_performance_from_sample(
         %{sample_entries: entries, sample_context: sample_context} = sample
       )
       when is_list(entries) do
    try do
      total_length_mbeats = Map.get(sample, :total_length_mbeats)

      performance =
        PerformanceAssembler.generate_sample(entries, sample_context,
          total_length_mbeats: total_length_mbeats
        )

      {:ok, performance}
    rescue
      error in [ArgumentError, RuntimeError] -> {:error, Exception.message(error)}
    end
  end

  defp normalize_map_string_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      Map.put(acc, normalized_key, value)
    end)
  end

  defp load_chord_lists(preferred_id) do
    chord_lists = ChordLists.list_lists()

    selected_id =
      cond do
        is_binary(preferred_id) and preferred_id != "" and
            Enum.any?(chord_lists, &(&1.id == preferred_id)) ->
          preferred_id

        chord_lists != [] ->
          chord_lists |> List.first() |> Map.fetch!(:id)

        true ->
          nil
      end

    entries =
      case selected_id do
        nil ->
          []

        id ->
          case ChordLists.fetch_list(id) do
            {:ok, list} -> enrich_chord_list_entries(list.entries)
            _ -> []
          end
      end

    {chord_lists, selected_id, entries}
  end

  defp chord_list_entry_label(entry) do
    values = chord_list_entry_values(entry)

    root =
      case parse_pitch_class(Map.get(values, "root")) do
        {:ok, root_pc} -> ChordSpec.root_label(root_pc)
        _ -> "?"
      end

    quality = Map.get(values, "quality", "?")
    octave = Map.get(values, "octave", "?")
    inversion = Map.get(values, "inversion", "?")

    "#{root} #{quality} (oct #{octave}, inv #{inversion})"
  end

  defp chord_list_entry_final_notes(entry) do
    Map.get(entry, :derived_final_notes, [])
  end

  defp chord_list_entry_values(entry) do
    parameters = Map.fetch!(entry, :parameters)
    Parameters.to_values_map(parameters)
  end

  defp enrich_chord_list_entries(entries) do
    Enum.map(entries, fn entry ->
      Map.put(entry, :derived_final_notes, derive_chord_list_entry_final_notes(entry))
    end)
  end

  defp derive_chord_list_entry_final_notes(%{parameters: %Parameters{} = parameters}) do
    try do
      parameters
      |> Parameters.to_chord_spec_attrs()
      |> ChordSpec.new!()
      |> Resolver.resolve()
    rescue
      _ -> []
    end
  end

  defp derive_chord_list_entry_final_notes(_entry), do: []

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

  defp highlighted_count(nil), do: 0

  defp highlighted_count(result) do
    result
    |> result_final_notes()
    |> Enum.uniq()
    |> Enum.count(&(&1 >= 21 and &1 <= 108))
  end

  defp keyboard_degree_labels(nil), do: %{}

  defp keyboard_degree_labels(result) do
    voiced_set = result |> Map.get(:voiced_chord_tones, []) |> MapSet.new()

    result
    |> Map.get(:final_note_details, [])
    |> Enum.reduce(%{}, fn detail, acc ->
      if MapSet.member?(voiced_set, detail.midi_note) do
        Map.put(acc, detail.midi_note, detail.degree_compound_preferred)
      else
        acc
      end
    end)
  end

  defp doubling_modes do
    [
      %{value: "auto", label: "Auto", description: "Root/fifth/third priority"},
      %{value: "root", label: "Root", description: "Repeat the root pitch class"},
      %{value: "top", label: "Top", description: "Repeat the top note"},
      %{value: "third", label: "Third", description: "Repeat the chord third"},
      %{value: "fifth", label: "Fifth", description: "Repeat the chord fifth family"},
      %{value: "guide_tones", label: "Guide", description: "Repeat third/seventh guide tones"},
      %{value: "bass", label: "Bass", description: "Repeat the current lowest voice"}
    ]
  end

  defp doubling_info_rows do
    [
      %{
        label: "Auto",
        explanation:
          "Uses the internal priority order root -> fifth -> third when adding voices.",
        availability: "Always"
      },
      %{
        label: "Root",
        explanation: "Repeats the root pitch class across octaves.",
        availability: "Always"
      },
      %{
        label: "Top",
        explanation: "Repeats the current top note of the voiced stack.",
        availability: "Always"
      },
      %{
        label: "Third",
        explanation: "Repeats the chord third (major or minor depending on quality).",
        availability: "Disabled for sus2 and sus4"
      },
      %{
        label: "Fifth",
        explanation: "Repeats the fifth family (perfect, flat, or sharp fifth).",
        availability: "Always"
      },
      %{
        label: "Guide",
        explanation:
          "Repeats guide tones (third and/or seventh) to strengthen harmonic function.",
        availability: "Disabled for sus2 and sus4"
      },
      %{
        label: "Bass",
        explanation: "Repeats the current lowest voice pitch class.",
        availability: "Always"
      }
    ]
  end

  defp doubling_mode_values do
    Enum.map(doubling_modes(), & &1.value)
  end

  defp doubling_mode_disabled?(mode, values) do
    auto_min_active? = voice_count_at_auto_min?(values)
    quality = Map.get(values, "quality", "")

    quality_restricted? =
      case mode do
        "third" -> quality in ["sus2", "sus4"]
        "guide_tones" -> quality in ["sus2", "sus4"]
        _ -> false
      end

    auto_min_active? or quality_restricted?
  end

  defp voice_count_at_auto_min?(values) when is_map(values) do
    minimum_voice_count_from_values(values) == voice_count_slider_value(values)
  end

  defp voice_count_at_auto_min?(_values), do: true

  defp keyboard_range_value(values, key) when is_map(values) and is_binary(key) do
    case Map.get(values, key) do
      nil ->
        nil

      "" ->
        nil

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
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
