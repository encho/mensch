defmodule MenschWeb.ProgressionLive do
  use MenschWeb, :live_view

  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Progression.Middleware.AppendChord
  alias Mensch.Harmony.Progression.Middleware.AppendScaleGeneratedChords
  alias Mensch.Harmony.Progression.Middleware.DeleteChordsFromProgression
  alias Mensch.Harmony.Progression.Middleware.EnsureBassAscending
  alias Mensch.Harmony.Progression.Middleware.ReorderChordProgression
  alias Mensch.Harmony.Progression.Middleware.TransposeAll
  alias Mensch.Harmony.Progression.Source.CreateEmptyProgression
  alias Mensch.Harmony.Resolver
  alias Mensch.Scale
  alias Mensch.Scale.ScaleRegistry
  alias MenschWeb.FullPianoKeyboard

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

  @transform_ids [
    "ensure_bass_ascending",
    "transpose_all",
    "reorder_chord_progression",
    "delete_chords_from_progression",
    "append_chord",
    "append_scale_generated_chords"
  ]

  @qualities ChordSpec.qualities() |> Enum.sort()

  @pitch_class_from_param Map.new(@pitch_classes, fn pitch_class ->
                            {Atom.to_string(pitch_class), pitch_class}
                          end)

  @quality_from_param Map.new(@qualities, fn quality ->
                        {Atom.to_string(quality), quality}
                      end)

  @shape_order [:triad, :seventh, :ninth, :eleventh, :thirteenth, :add6, :six_nine]

  @impl true
  def mount(params, _session, socket) do
    scratch_timestamp = NaiveDateTime.local_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:scale_families, ScaleRegistry.all())
      |> assign(:chord_strategies, Scale.chord_strategy_options())
      |> assign(:blueprint_progression, nil)
      |> assign(:scratch_timestamp, scratch_timestamp)
      |> assign(:transforms, [])
      |> assign(:stage_progressions, [])
      |> assign(:progression, nil)
      |> assign(:chords, [])
      |> assign(:save_modal_open, false)
      |> assign(:save_stage_index, nil)
      |> assign(:save_name, "")
      |> assign(:save_description, "")
      |> assign(:preview_note_channels, [])
      |> assign(:preview_stop_ref, nil)
      |> assign(:error_message, nil)
      |> assign_blueprint_from_params(params)
      |> run_pipeline()

    {:ok, socket}
  end

  @impl true
  def handle_event("add_transform", params, socket) do
    transform_id = Map.get(params, "transform_id", hd(@transform_ids))
    transform = default_transform_config(valid_transform_id(transform_id))
    stage_index = Map.get(params, "stage_index", length(socket.assigns.transforms) - 1)

    transforms = insert_transform_after_stage(socket.assigns.transforms, stage_index, transform)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event("remove_transform", %{"index" => index}, socket) do
    transforms = remove_transform_by_index(socket.assigns.transforms, index)
    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event(
        "set_transform_bool",
        %{"index" => index, "field" => field, "value" => value},
        socket
      ) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case {field, value} do
          {"include_foreign_bass", "true"} -> Map.put(opts, "include_foreign_bass", true)
          {"include_foreign_bass", "false"} -> Map.put(opts, "include_foreign_bass", false)
          _ -> opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event(
        "set_transform_integer",
        %{"index" => index, "field" => field, "value" => value},
        socket
      ) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case parse_integer(value, "transform field") do
          {:ok, parsed} -> Map.put(opts, field, parsed)
          {:error, _reason} -> opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event("set_transform_scale_family", %{"index" => index, "family" => family}, socket) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case parse_family(family, socket.assigns.scale_families) do
          {:ok, family_id} ->
            family_value = Atom.to_string(family_id)
            default_mode = default_mode_for_family(socket.assigns.scale_families, family_id)

            opts
            |> Map.put("family", family_value)
            |> Map.put("scale_mode", default_mode)

          {:error, _reason} ->
            opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event(
        "set_transform_scale_mode",
        %{"index" => index, "scale_mode" => scale_mode},
        socket
      ) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case parse_scale_mode(scale_mode) do
          {:ok, mode} -> Map.put(opts, "scale_mode", Integer.to_string(mode))
          {:error, _reason} -> opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event("set_transform_strategy", %{"index" => index, "strategy" => strategy}, socket) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case parse_strategy(strategy, socket.assigns.chord_strategies) do
          {:ok, _strategy} ->
            strategy_value = strategy

            default_shape =
              default_shape_for_strategy(strategy_value, socket.assigns.chord_strategies)

            opts
            |> Map.put("strategy", strategy_value)
            |> Map.put("shape", default_shape)

          {:error, _reason} ->
            opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event("set_transform_shape", %{"index" => index, "shape" => shape}, socket) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case parse_shape(shape) do
          {:ok, parsed_shape} -> Map.put(opts, "shape", Atom.to_string(parsed_shape))
          {:error, _reason} -> opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event("set_transform_quality", %{"index" => index, "quality" => quality}, socket) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        case parse_quality(quality) do
          {:ok, parsed_quality} -> Map.put(opts, "quality", Atom.to_string(parsed_quality))
          {:error, _reason} -> opts
        end
      end)

    {:noreply, assign(socket, :transforms, transforms)}
  end

  @impl true
  def handle_event(
        "set_transform_pitch_class",
        %{"index" => index, "field" => field, "pitch_class" => pitch_class},
        socket
      ) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        if field in ["tonic", "foreign_bass"] do
          Map.put(opts, field, pitch_class)
        else
          opts
        end
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event(
        "move_reorder_chord",
        %{"index" => index, "position" => position, "direction" => direction},
        socket
      ) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        transform_index = parse_non_negative_integer(index)
        stage_progression = Enum.at(socket.assigns.stage_progressions, transform_index)
        chord_count = if stage_progression, do: length(stage_progression.chords), else: 0

        order = normalize_reorder_order(Map.get(opts, "order"), chord_count)
        position_value = parse_non_negative_integer(position)
        delta = if direction == "up", do: -1, else: 1
        moved_order = move_item_by_position(order, position_value, delta)

        Map.put(opts, "order", moved_order)
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event(
        "toggle_delete_chord",
        %{"index" => index, "chord_index" => chord_index},
        socket
      ) do
    transforms =
      update_transform_opts(socket.assigns.transforms, index, fn opts ->
        transform_index = parse_non_negative_integer(index)
        stage_progression = Enum.at(socket.assigns.stage_progressions, transform_index)
        chord_count = if stage_progression, do: length(stage_progression.chords), else: 0

        current_deleted_indices =
          normalize_deleted_indices(Map.get(opts, "deleted_indices"), chord_count)

        parsed_chord_index = parse_non_negative_integer(chord_index)

        updated_deleted_indices =
          if parsed_chord_index in current_deleted_indices do
            Enum.reject(current_deleted_indices, &(&1 == parsed_chord_index))
          else
            normalize_deleted_indices(
              current_deleted_indices ++ [parsed_chord_index],
              chord_count
            )
          end

        Map.put(opts, "deleted_indices", updated_deleted_indices)
      end)

    {:noreply, assign_transforms_and_run_pipeline(socket, transforms)}
  end

  @impl true
  def handle_event("open_save_modal", params, socket) do
    stage_index =
      params
      |> Map.get("stage_index", max(length(socket.assigns.stage_progressions) - 1, 0))
      |> parse_stage_index(socket.assigns.stage_progressions)

    case Enum.at(socket.assigns.stage_progressions, stage_index) do
      %{chords: chords} when is_list(chords) and chords != [] ->
        {default_name, default_description} =
          default_save_metadata(
            socket.assigns.blueprint_progression,
            stage_index,
            socket.assigns.scratch_timestamp
          )

        {:noreply,
         socket
         |> assign(:save_modal_open, true)
         |> assign(:save_stage_index, stage_index)
         |> assign(:save_name, default_name)
         |> assign(:save_description, default_description)}

      _ ->
        {:noreply, put_flash(socket, :error, "No chords to save")}
    end
  end

  @impl true
  def handle_event("close_save_modal", _params, socket) do
    {:noreply, socket |> assign(:save_modal_open, false) |> assign(:save_stage_index, nil)}
  end

  @impl true
  def handle_event("save_progression", %{"progression" => params}, socket) do
    name = Map.get(params, "name", "")
    description = Map.get(params, "description", "")

    stage_index =
      socket.assigns.save_stage_index || max(length(socket.assigns.stage_progressions) - 1, 0)

    case Enum.at(socket.assigns.stage_progressions, stage_index) do
      %{chords: chords} when is_list(chords) and chords != [] ->
        case ChordProgressions.create_progression(name, description, chords) do
          {:ok, _record} ->
            {:noreply,
             socket
             |> assign(:save_modal_open, false)
             |> assign(:save_stage_index, nil)
             |> put_flash(:info, "Progression saved")}

          {:error, :name_required} ->
            {:noreply, put_flash(socket, :error, "Name is required")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No progression to save")}
    end
  end

  @impl true
  def handle_event("play_chord", %{"index" => index} = params, socket) do
    parsed_stage_index =
      params
      |> Map.get("stage_index", max(length(socket.assigns.stage_progressions) - 1, 0))
      |> parse_stage_index(socket.assigns.stage_progressions)

    chord =
      case Integer.parse(to_string(index)) do
        {parsed, ""} ->
          socket.assigns.stage_progressions
          |> Enum.at(parsed_stage_index)
          |> then(fn progression -> if progression, do: progression.chords, else: [] end)
          |> Enum.at(parsed)

        _ ->
          nil
      end

    case chord do
      %ChordSpec{} = chord_spec -> play_notes_for_3s(socket, Resolver.resolve(chord_spec))
      _ -> {:noreply, put_flash(socket, :error, "Invalid chord")}
    end
  end

  @impl true
  def handle_event("play_append_transform_chord", %{"index" => index}, socket) do
    transform = Enum.at(socket.assigns.transforms, parse_non_negative_integer(index))

    with %{id: "append_chord", opts: opts} <- transform,
         {:ok, chord_spec} <- append_chord_spec_from_opts(opts) do
      play_notes_for_3s(socket, Resolver.resolve(chord_spec))
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid append chord settings")}
    end
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
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
      |> assign(:stage_cards, build_stage_cards(assigns.stage_progressions))

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:progression}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Chord Progression Lab"
          subtitle="Build a progression pipeline with one source and append-only transforms."
        />

        <div class="flex items-center justify-end">
          <.link
            navigate={~p"/chord-progressions"}
            class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
          >
            View Saved Progressions
          </.link>
        </div>

        <div class="space-y-4">
          <div :if={@error_message} class="rounded-sm border border-rose-500/40 bg-rose-950/30 p-3">
            <p class="font-mono text-xs text-rose-200">{@error_message}</p>
          </div>

          <div class="space-y-4">
            <div
              :for={stage <- @stage_cards}
              class="space-y-3"
            >
              <.pipeline_card body_class="space-y-4" card_bg_class="bg-zinc-950/25">
                <:header>
                  <.pipeline_card_header
                    kind={:stage}
                    title={
                      if stage.index == 0,
                        do: "Stage 0 · Initial Progression",
                        else: "Stage #{stage.index} · Result"
                    }
                  >
                    <:actions>
                      <button
                        id={"save-stage-#{stage.index}"}
                        type="button"
                        phx-click="open_save_modal"
                        phx-value-stage_index={stage.index}
                        disabled={stage.chord_cards == []}
                        class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                      >
                        Save This Stage
                      </button>
                    </:actions>
                  </.pipeline_card_header>
                </:header>

                <div
                  :if={stage.chord_cards == []}
                  class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
                >
                  <p class="font-mono text-xs text-zinc-400">No chords in this stage yet.</p>
                </div>

                <div :if={stage.chord_cards != []} class="space-y-4">
                  <div
                    :for={card <- stage.chord_cards}
                    class="rounded-sm border border-zinc-700/60 bg-zinc-950/65 p-3"
                  >
                    <div class="flex flex-col gap-3 md:flex-row md:items-start">
                      <button
                        type="button"
                        phx-click="play_chord"
                        phx-value-stage_index={stage.index}
                        phx-value-index={card.index}
                        class="w-56 shrink-0 rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-2 text-center font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
                      >
                        {card.degree} · {card.symbol}
                      </button>

                      <div class="min-w-0 flex-1 md:max-w-4xl">
                        <div class="rounded-md border border-zinc-700/70 bg-zinc-950 p-2">
                          <FullPianoKeyboard.keyboard
                            id={"progression-keyboard-#{stage.index}-#{card.index}"}
                            keys={card.keyboard_keys}
                            height_class="h-28"
                            show_bottom_lane={false}
                            color_mode={:dark}
                          />
                        </div>

                        <p class="mt-2 font-mono text-[11px] text-zinc-400">{card.named_notes}</p>
                      </div>
                    </div>
                  </div>
                </div>
              </.pipeline_card>

              <div :if={stage.index == length(@transforms)}>
                <.pipeline_card body_class="" card_bg_class="bg-zinc-950/20">
                  <:header>
                    <.pipeline_card_header kind={:transforms} title="Transforms" />
                  </:header>

                  <div class="flex flex-wrap items-start justify-start gap-2">
                    <div
                      :for={{group, group_index} <- Enum.with_index(transform_groups())}
                      class={[
                        "space-y-2",
                        group_index > 0 && "border-l border-zinc-700/70 pl-2"
                      ]}
                    >
                      <p class="font-mono text-[11px] uppercase tracking-wide text-zinc-500">
                        {group.label}
                      </p>

                      <div class="flex flex-wrap items-center gap-2">
                        <button
                          :for={id <- group.ids}
                          type="button"
                          phx-click="add_transform"
                          phx-value-stage_index={stage.index}
                          phx-value-transform_id={id}
                          title={transform_label(id)}
                          aria-label={transform_label(id)}
                          class="inline-flex h-8 w-8 items-center justify-center rounded-sm border border-zinc-600 bg-zinc-900/70 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                        >
                          <%= case id do %>
                            <% "append_chord" -> %>
                              <span class="relative inline-flex h-4 w-5 items-end justify-center">
                                <span class="h-3 w-1 rounded-[1px] bg-zinc-100"></span>
                                <span class="h-3 w-1 rounded-[1px] bg-zinc-100"></span>
                                <span class="h-3 w-1 rounded-[1px] bg-zinc-100"></span>
                                <span class="pointer-events-none absolute left-[7px] top-0 h-2 w-1 rounded-[1px] bg-zinc-800"></span>
                                <span class="pointer-events-none absolute left-[11px] top-0 h-2 w-1 rounded-[1px] bg-zinc-800"></span>
                              </span>
                            <% "append_scale_generated_chords" -> %>
                              <span class="inline-flex h-4 w-5 items-end justify-between">
                                <span class="h-1 w-1.5 rounded-[1px] bg-zinc-100"></span>
                                <span class="h-2 w-1.5 rounded-[1px] bg-zinc-100"></span>
                                <span class="h-3 w-1.5 rounded-[1px] bg-zinc-100"></span>
                              </span>
                            <% _ -> %>
                              <.icon name={transform_icon(id)} class="h-4 w-4" />
                          <% end %>
                          <span class="sr-only">{transform_label(id)}</span>
                        </button>
                      </div>
                    </div>
                  </div>
                </.pipeline_card>
              </div>

              <%= if stage.index < length(@transforms) do %>
                <% transform = Enum.at(@transforms, stage.index) %>
                <% preview =
                  if transform && transform.id == "append_chord",
                    do: append_chord_preview(transform.opts),
                    else: nil %>

                <.pipeline_card body_class="space-y-3" card_bg_class="bg-zinc-950/20">
                  <:header>
                    <.pipeline_card_header
                      kind={:transform}
                      title={"Transform #{stage.index + 1}: #{transform_label(transform.id)}"}
                    >
                      <:actions>
                        <button
                          type="button"
                          phx-click="remove_transform"
                          phx-value-index={stage.index}
                          class="rounded-sm border border-rose-500/50 bg-rose-900/20 px-2 py-1 font-mono text-[11px] text-rose-200 transition-colors duration-150 hover:bg-rose-900/40"
                        >
                          Remove
                        </button>
                      </:actions>
                    </.pipeline_card_header>
                  </:header>

                  <%= if transform.id == "ensure_bass_ascending" do %>
                    <label class="inline-flex items-center gap-2 font-mono text-xs text-zinc-200">
                      <input
                        type="checkbox"
                        checked={transform.opts["include_foreign_bass"]}
                        phx-click="set_transform_bool"
                        phx-value-index={stage.index}
                        phx-value-field="include_foreign_bass"
                        phx-value-value={
                          if(transform.opts["include_foreign_bass"], do: "false", else: "true")
                        }
                      /> Include foreign bass
                    </label>
                  <% end %>

                  <%= if transform.id == "transpose_all" do %>
                    <div class="space-y-2 max-w-xl">
                      <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                        Semitones
                      </span>

                      <form phx-input="set_transform_integer" phx-change="set_transform_integer">
                        <input type="hidden" name="index" value={stage.index} />
                        <input type="hidden" name="field" value="semitones" />
                        <input
                          type="range"
                          min="-24"
                          max="24"
                          step="1"
                          name="value"
                          class="w-full accent-emerald-300"
                          value={transform.opts["semitones"]}
                        />
                      </form>

                      <form phx-input="set_transform_integer" phx-change="set_transform_integer">
                        <input type="hidden" name="index" value={stage.index} />
                        <input type="hidden" name="field" value="semitones" />
                        <input
                          type="number"
                          min="-24"
                          max="24"
                          step="1"
                          name="value"
                          class="w-28 rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                          value={transform.opts["semitones"]}
                        />
                      </form>
                    </div>
                  <% end %>

                  <%= if transform.id == "reorder_chord_progression" do %>
                    <% stage_cards = stage.chord_cards || [] %>
                    <% reorder_order =
                      normalize_reorder_order(transform.opts["order"], length(stage_cards)) %>
                    <% ordered_cards = reorder_cards_for_order(stage_cards, reorder_order) %>

                    <div class="space-y-2">
                      <p class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                        Reorder Chords
                      </p>

                      <div
                        :if={ordered_cards == []}
                        class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
                      >
                        <p class="font-mono text-xs text-zinc-400">
                          No chords available to reorder.
                        </p>
                      </div>

                      <div :if={ordered_cards != []} class="space-y-2">
                        <div
                          :for={{card, position} <- Enum.with_index(ordered_cards)}
                          class="flex items-center gap-2 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2"
                        >
                          <span class="w-6 text-center font-mono text-xs text-zinc-400">{position + 1}</span>
                          <div class="min-w-0 flex-1">
                            <p class="truncate font-mono text-xs text-zinc-100">
                              {card.degree} · {card.symbol}
                            </p>
                            <p class="font-mono text-[11px] text-zinc-500">{card.named_notes}</p>
                          </div>

                          <div class="flex items-center gap-1">
                            <button
                              type="button"
                              phx-click="move_reorder_chord"
                              phx-value-index={stage.index}
                              phx-value-position={position}
                              phx-value-direction="up"
                              disabled={position == 0}
                              class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-[11px] text-zinc-200 enabled:hover:border-zinc-500 disabled:opacity-40"
                            >
                              Up
                            </button>
                            <button
                              type="button"
                              phx-click="move_reorder_chord"
                              phx-value-index={stage.index}
                              phx-value-position={position}
                              phx-value-direction="down"
                              disabled={position == length(ordered_cards) - 1}
                              class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-[11px] text-zinc-200 enabled:hover:border-zinc-500 disabled:opacity-40"
                            >
                              Down
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>

                  <%= if transform.id == "delete_chords_from_progression" do %>
                    <% stage_cards = stage.chord_cards || [] %>
                    <% deleted_indices =
                      normalize_deleted_indices(
                        transform.opts["deleted_indices"],
                        length(stage_cards)
                      ) %>

                    <div class="space-y-2">
                      <p class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                        Delete Chords
                      </p>

                      <div
                        :if={stage_cards == []}
                        class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
                      >
                        <p class="font-mono text-xs text-zinc-400">No chords available.</p>
                      </div>

                      <div :if={stage_cards != []} class="space-y-2">
                        <div
                          :for={card <- stage_cards}
                          class={
                            if card.index in deleted_indices,
                              do:
                                "flex items-center gap-2 rounded-sm border border-rose-700/70 bg-rose-950/20 p-2",
                              else:
                                "flex items-center gap-2 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2"
                          }
                        >
                          <span class="w-6 text-center font-mono text-xs text-zinc-400">{card.index +
                            1}</span>
                          <div class="min-w-0 flex-1">
                            <p class="truncate font-mono text-xs text-zinc-100">
                              {card.degree} · {card.symbol}
                            </p>
                            <p class="font-mono text-[11px] text-zinc-500">{card.named_notes}</p>
                          </div>

                          <button
                            type="button"
                            phx-click="toggle_delete_chord"
                            phx-value-index={stage.index}
                            phx-value-chord_index={card.index}
                            class={
                              if card.index in deleted_indices,
                                do:
                                  "rounded-sm border border-zinc-500 px-2 py-1 font-mono text-[11px] text-zinc-200 hover:border-zinc-400",
                                else:
                                  "rounded-sm border border-rose-800/80 px-2 py-1 font-mono text-[11px] text-rose-200 hover:border-rose-700"
                            }
                          >
                            {if card.index in deleted_indices, do: "Restore", else: "Delete"}
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>

                  <%= if transform.id == "append_chord" do %>
                    <div class="space-y-3">
                      <div class="max-w-xl">
                        <MenschWeb.PitchClassKeyboard.mini
                          id={"progression-append-root-#{stage.index}"}
                          label="Root"
                          event="set_transform_pitch_class"
                          selected_key={
                            selected_tonic_keyboard_key(%{
                              opts: %{"tonic" => transform.opts["tonic"]}
                            })
                          }
                          selected_key_color="#f6d365"
                          value_index={stage.index}
                          value_field="tonic"
                        />
                      </div>

                      <div class="space-y-1">
                        <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                          Quality
                        </label>
                        <div class="flex flex-wrap gap-2">
                          <button
                            :for={quality <- qualities()}
                            type="button"
                            phx-click="set_transform_quality"
                            phx-value-index={stage.index}
                            phx-value-quality={Atom.to_string(quality)}
                            class={
                              toggle_button_classes(
                                transform.opts["quality"] == Atom.to_string(quality)
                              )
                            }
                          >
                            {Atom.to_string(quality)}
                          </button>
                        </div>
                      </div>

                      <div class="grid gap-3 md:grid-cols-2">
                        <label class="space-y-1">
                          <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                            Octave
                          </span>
                          <input
                            type="number"
                            class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                            value={transform.opts["octave"]}
                            phx-blur="set_transform_integer"
                            phx-value-index={stage.index}
                            phx-value-field="octave"
                          />
                        </label>

                        <label class="space-y-1">
                          <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                            Inversion
                          </span>
                          <input
                            type="number"
                            min="0"
                            class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                            value={transform.opts["inversion"]}
                            phx-blur="set_transform_integer"
                            phx-value-index={stage.index}
                            phx-value-field="inversion"
                          />
                        </label>
                      </div>

                      <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3 space-y-2">
                        <div class="flex items-center justify-between gap-2">
                          <div class="min-w-0">
                            <p class="truncate font-mono text-xs text-zinc-100">
                              {if preview, do: preview.symbol, else: "Preview unavailable"}
                            </p>
                            <p :if={preview} class="font-mono text-[11px] text-zinc-400">
                              {preview.named_notes}
                            </p>
                            <p :if={!preview} class="font-mono text-[11px] text-rose-300">
                              Invalid append chord settings
                            </p>
                          </div>

                          <button
                            type="button"
                            phx-click="play_append_transform_chord"
                            phx-value-index={stage.index}
                            disabled={!preview}
                            class="rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 enabled:hover:bg-emerald-400/30 disabled:cursor-not-allowed disabled:opacity-40"
                          >
                            Play
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>

                  <%= if transform.id == "append_scale_generated_chords" do %>
                    <% transform_source = %{opts: transform.opts} %>
                    <% transform_scale_family_options =
                      source_scale_family_options(@scale_families, transform_source) %>
                    <% transform_scale_mode_options =
                      source_scale_mode_options(@scale_families, transform_source) %>
                    <% transform_strategy_options =
                      source_strategy_options(@chord_strategies, transform_source) %>
                    <% transform_shape_options =
                      source_shape_options(@chord_strategies, transform_source) %>

                    <div class="space-y-3">
                      <div class="max-w-xl">
                        <MenschWeb.PitchClassKeyboard.mini
                          id={"progression-transform-scale-tonic-#{stage.index}"}
                          label="Tonic"
                          event="set_transform_pitch_class"
                          selected_key={
                            selected_tonic_keyboard_key(%{
                              opts: %{"tonic" => transform.opts["tonic"]}
                            })
                          }
                          selected_key_color="#f6d365"
                          value_index={stage.index}
                          value_field="tonic"
                        />
                      </div>

                      <div class="grid gap-3 md:grid-cols-2">
                        <label class="space-y-1">
                          <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                            Scale Family
                          </span>
                          <form phx-change="set_transform_scale_family">
                            <input type="hidden" name="index" value={stage.index} />
                            <select
                              name="family"
                              class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                            >
                              <option
                                :for={item <- transform_scale_family_options}
                                value={item.value}
                                selected={item.selected}
                              >
                                {item.label}
                              </option>
                            </select>
                          </form>
                        </label>

                        <label class="space-y-1">
                          <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                            Mode
                          </span>
                          <form phx-change="set_transform_scale_mode">
                            <input type="hidden" name="index" value={stage.index} />
                            <select
                              name="scale_mode"
                              class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                            >
                              <option
                                :for={item <- transform_scale_mode_options}
                                value={item.value}
                                selected={item.selected}
                              >
                                {item.label}
                              </option>
                            </select>
                          </form>
                        </label>
                      </div>

                      <div class="grid gap-3 md:grid-cols-2">
                        <label class="space-y-1">
                          <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                            Strategy
                          </span>
                          <form phx-change="set_transform_strategy">
                            <input type="hidden" name="index" value={stage.index} />
                            <select
                              name="strategy"
                              class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                            >
                              <option
                                :for={item <- transform_strategy_options}
                                value={item.value}
                                selected={item.selected}
                              >
                                {item.label}
                              </option>
                            </select>
                          </form>
                        </label>

                        <label class="space-y-1">
                          <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                            Chord Shape
                          </span>
                          <form phx-change="set_transform_shape">
                            <input type="hidden" name="index" value={stage.index} />
                            <select
                              name="shape"
                              class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                            >
                              <option
                                :for={item <- transform_shape_options}
                                value={item.value}
                                selected={item.selected}
                              >
                                {item.label}
                              </option>
                            </select>
                          </form>
                        </label>
                      </div>
                    </div>
                  <% end %>
                </.pipeline_card>
              <% end %>
            </div>
          </div>
        </div>

        <div
          :if={@save_modal_open}
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-4"
        >
          <div class="w-full max-w-lg rounded-sm border border-zinc-700 bg-zinc-950 p-4">
            <div class="mb-3 flex items-center justify-between">
              <h3 class="font-mono text-sm text-zinc-100">Save Chord Progression</h3>
              <button
                type="button"
                phx-click="close_save_modal"
                class="rounded-sm border border-zinc-700 px-2 py-1 font-mono text-[11px] text-zinc-300 hover:border-zinc-500"
              >
                Close
              </button>
            </div>

            <form phx-submit="save_progression" class="space-y-3">
              <label class="space-y-1 block">
                <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Name
                </span>
                <input
                  type="text"
                  name="progression[name]"
                  value={@save_name}
                  class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                  required
                />
              </label>

              <label class="space-y-1 block">
                <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Description
                </span>
                <textarea
                  name="progression[description]"
                  rows="3"
                  class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                >{@save_description}</textarea>
              </label>

              <div class="flex items-center justify-end gap-2 pt-1">
                <button
                  type="button"
                  phx-click="close_save_modal"
                  class="rounded-sm border border-zinc-700 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-200 hover:border-zinc-500"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-emerald-100 hover:bg-emerald-400/30"
                >
                  Save
                </button>
              </div>
            </form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :body_class, :string, default: ""
  attr :card_bg_class, :string, default: "bg-zinc-950/20"
  slot :header, required: true
  slot :inner_block, required: true

  defp pipeline_card(assigns) do
    ~H"""
    <div class={["overflow-hidden rounded-sm border border-zinc-600/80", @card_bg_class]}>
      {render_slot(@header)}
      <div class={["p-3", @body_class]}>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :title, :string, required: true
  slot :actions

  defp pipeline_card_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 border-b border-zinc-700/70 bg-zinc-900/30 px-3 py-2.5">
      <div class="flex min-w-0 items-center gap-2">
        <span class={[
          "inline-flex items-center justify-center rounded-sm border p-1",
          card_header_cue_classes(@kind)
        ]}>
          <.icon name={card_header_icon(@kind)} class="h-3 w-3" />
        </span>
        <p class="truncate font-mono text-[11px] uppercase tracking-wide text-zinc-300">{@title}</p>
      </div>

      <div :if={@actions != []} class="shrink-0">{render_slot(@actions)}</div>
    </div>
    """
  end

  defp card_header_icon(:stage), do: "hero-squares-2x2"
  defp card_header_icon(:transforms), do: "hero-wrench-screwdriver"
  defp card_header_icon(:transform), do: "hero-adjustments-horizontal"
  defp card_header_icon(_), do: "hero-cog-6-tooth"

  defp card_header_cue_classes(:stage), do: "border-amber-500/50 bg-amber-900/40 text-amber-200"
  defp card_header_cue_classes(:transforms), do: "border-sky-500/50 bg-sky-900/40 text-sky-200"

  defp card_header_cue_classes(:transform),
    do: "border-emerald-500/50 bg-emerald-900/40 text-emerald-200"

  defp card_header_cue_classes(_), do: "border-zinc-500/60 bg-zinc-800/80 text-zinc-100"

  defp run_pipeline(socket) do
    with {:ok, source_fn} <- {:ok, source_from_blueprint(socket.assigns.blueprint_progression)},
         {:ok, source_progression} <- source_fn.(),
         {:ok, stage_progressions} <-
           build_stage_progressions(source_progression, socket.assigns.transforms),
         progression when is_struct(progression, ChordProgression) <-
           List.last(stage_progressions) do
      socket
      |> assign(:stage_progressions, stage_progressions)
      |> assign(:progression, progression)
      |> assign(:chords, progression.chords)
      |> assign(:error_message, nil)
    else
      nil ->
        socket
        |> assign(:stage_progressions, [])
        |> assign(:progression, nil)
        |> assign(:chords, [])
        |> assign(:error_message, "No progression stages available")

      {:error, reason} ->
        socket
        |> assign(:stage_progressions, [])
        |> assign(:progression, nil)
        |> assign(:chords, [])
        |> assign(:error_message, format_error(reason))
    end
  end

  defp assign_transforms_and_run_pipeline(socket, transforms) do
    socket
    |> assign(:transforms, transforms)
    |> run_pipeline()
  end

  defp build_stage_progressions(%ChordProgression{} = source_progression, transforms)
       when is_list(transforms) do
    transforms
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [source_progression]}, fn {transform, transform_index},
                                                         {:ok, acc} ->
      with {:ok, transform_fun} <- transform_to_fun(transform),
           current when is_struct(current, ChordProgression) <- List.last(acc),
           {:ok, next_progression} <- transform_fun.(current) do
        {:cont, {:ok, acc ++ [next_progression]}}
      else
        {:error, reason} -> {:halt, {:error, {:transform_failed, transform_index, reason}}}
        _ -> {:halt, {:error, {:transform_failed, transform_index, :invalid_result}}}
      end
    end)
  end

  defp build_stage_progressions(_source_progression, _transforms),
    do: {:error, {:source_failed, :invalid_source}}

  defp transform_to_fun(%{id: "ensure_bass_ascending", opts: opts}) do
    include_foreign_bass = Map.get(opts, "include_foreign_bass", false)
    {:ok, EnsureBassAscending.middleware(include_foreign_bass: include_foreign_bass)}
  end

  defp transform_to_fun(%{id: "transpose_all", opts: opts}) do
    with {:ok, semitones} <- parse_integer(Map.get(opts, "semitones"), "semitones") do
      {:ok, TransposeAll.middleware(semitones: semitones)}
    end
  end

  defp transform_to_fun(%{id: "reorder_chord_progression", opts: opts}) do
    order =
      case Map.get(opts, "order") do
        value when is_list(value) -> value
        _ -> []
      end

    {:ok, ReorderChordProgression.middleware(order: order)}
  end

  defp transform_to_fun(%{id: "delete_chords_from_progression", opts: opts}) do
    deleted_indices =
      case Map.get(opts, "deleted_indices") do
        value when is_list(value) -> value
        _ -> []
      end

    {:ok, DeleteChordsFromProgression.middleware(deleted_indices: deleted_indices)}
  end

  defp transform_to_fun(%{id: "append_chord", opts: opts}) do
    with {:ok, chord_spec} <- append_chord_spec_from_opts(opts) do
      {:ok, AppendChord.middleware(chord_spec: chord_spec)}
    end
  end

  defp transform_to_fun(%{id: "append_scale_generated_chords", opts: opts}) do
    with {:ok, tonic} <- parse_tonic(Map.get(opts, "tonic")),
         {:ok, family} <- parse_family(Map.get(opts, "family"), ScaleRegistry.all()),
         {:ok, mode} <- parse_scale_mode(Map.get(opts, "scale_mode")),
         {:ok, strategy} <-
           parse_strategy(Map.get(opts, "strategy"), Scale.chord_strategy_options()),
         {:ok, shape} <-
           parse_shape_for_strategy(
             Map.get(opts, "shape"),
             Map.get(opts, "strategy"),
             Scale.chord_strategy_options()
           ) do
      {:ok,
       AppendScaleGeneratedChords.middleware(
         scale: %{tonic: tonic, family: family, mode: mode},
         strategy: strategy,
         shape: shape,
         spelling_mode: :practical,
         render_defaults: %{octave: 3, inversion: 0}
       )}
    end
  end

  defp transform_to_fun(_), do: {:error, :invalid_transform}

  defp assign_blueprint_from_params(socket, %{"blueprint_id" => blueprint_id})
       when is_binary(blueprint_id) and blueprint_id != "" do
    case ChordProgressions.fetch_progression(blueprint_id) do
      {:ok, %{progression: %ChordProgression{} = progression}} ->
        assign(socket, :blueprint_progression, progression)

      {:ok, _record} ->
        socket
        |> assign(:blueprint_progression, nil)
        |> put_flash(:error, "Invalid blueprint progression")

      {:error, :not_found} ->
        socket
        |> assign(:blueprint_progression, nil)
        |> put_flash(:error, "Blueprint progression not found")

      {:error, reason} ->
        socket
        |> assign(:blueprint_progression, nil)
        |> put_flash(:error, "Failed to load blueprint: #{inspect(reason)}")
    end
  end

  defp assign_blueprint_from_params(socket, _params),
    do: assign(socket, :blueprint_progression, nil)

  defp source_from_blueprint(%ChordProgression{} = blueprint_progression) do
    fn -> {:ok, blueprint_progression} end
  end

  defp source_from_blueprint(_), do: CreateEmptyProgression.source()

  defp default_save_metadata(%ChordProgression{} = blueprint_progression, stage_index, _timestamp) do
    blueprint_name =
      blueprint_progression
      |> Map.get(:name, "Chord Progression")
      |> to_string()
      |> String.trim()

    base_name = if blueprint_name == "", do: "Chord Progression", else: blueprint_name

    blueprint_description =
      blueprint_progression
      |> Map.get(:description, "")
      |> to_string()
      |> String.trim()

    name =
      if stage_index == 0,
        do: "#{base_name} (variation)",
        else: "#{base_name} (variation · step #{stage_index})"

    description_prefix =
      if stage_index == 0,
        do: "Variation of #{base_name}.",
        else: "Variation of #{base_name}, after step #{stage_index}."

    description =
      if blueprint_description == "" do
        description_prefix
      else
        "#{description_prefix} #{blueprint_description}"
      end

    {name, description}
  end

  defp default_save_metadata(nil, stage_index, timestamp) do
    base_name = "Progression #{timestamp}"

    name = "#{base_name} (step #{stage_index})"

    description =
      if stage_index == 0,
        do: "Created from empty source at #{timestamp}.",
        else: "Created from empty source at #{timestamp}, after step #{stage_index}."

    {name, description}
  end

  defp transform_groups do
    [
      %{label: "GENERATION", ids: ["append_chord", "append_scale_generated_chords"]},
      %{label: "HARMONY", ids: ["ensure_bass_ascending", "transpose_all"]},
      %{
        label: "STRUCTURE",
        ids: ["reorder_chord_progression", "delete_chords_from_progression"]
      }
    ]
  end

  defp qualities, do: @qualities

  defp valid_transform_id(transform_id) when transform_id in @transform_ids, do: transform_id
  defp valid_transform_id(_), do: hd(@transform_ids)

  defp transform_label("ensure_bass_ascending"), do: "Ensure Bass Ascending"
  defp transform_label("transpose_all"), do: "Transpose All"
  defp transform_label("reorder_chord_progression"), do: "Reorder Chord Progression"
  defp transform_label("delete_chords_from_progression"), do: "Delete Chords From Progression"
  defp transform_label("append_chord"), do: "Append Chord"
  defp transform_label("append_scale_generated_chords"), do: "Append Scale-Generated Chords"
  defp transform_label(_), do: "Unknown Transform"

  defp transform_icon("ensure_bass_ascending"), do: "hero-arrow-trending-up"
  defp transform_icon("transpose_all"), do: "hero-arrows-up-down"
  defp transform_icon("reorder_chord_progression"), do: "hero-queue-list"
  defp transform_icon("delete_chords_from_progression"), do: "hero-trash"
  defp transform_icon("append_chord"), do: "hero-plus-circle"
  defp transform_icon("append_scale_generated_chords"), do: "hero-sparkles"
  defp transform_icon(_), do: "hero-cog-6-tooth"

  defp default_transform_config("ensure_bass_ascending") do
    %{id: "ensure_bass_ascending", opts: %{"include_foreign_bass" => false}}
  end

  defp default_transform_config("transpose_all") do
    %{id: "transpose_all", opts: %{"semitones" => 12}}
  end

  defp default_transform_config("reorder_chord_progression") do
    %{id: "reorder_chord_progression", opts: %{"order" => []}}
  end

  defp default_transform_config("delete_chords_from_progression") do
    %{id: "delete_chords_from_progression", opts: %{"deleted_indices" => []}}
  end

  defp default_transform_config("append_chord") do
    %{
      id: "append_chord",
      opts: %{
        "tonic" => "c",
        "quality" => "maj",
        "octave" => 3,
        "inversion" => 0,
        "voicing_type" => "close",
        "center_note" => 60,
        "range_min" => nil,
        "range_max" => nil,
        "voice_count" => nil,
        "doubling" => "auto",
        "inversion_resolution_mode" => "per_step_centered",
        "expanded" => true
      }
    }
  end

  defp default_transform_config("append_scale_generated_chords") do
    %{
      id: "append_scale_generated_chords",
      opts: %{
        "tonic" => "c",
        "family" => "major",
        "scale_mode" => "1",
        "strategy" => "tertian",
        "shape" => "triad",
        "expanded" => true
      }
    }
  end

  defp default_transform_config(_), do: default_transform_config("ensure_bass_ascending")

  defp remove_transform_by_index(transforms, index_param) do
    case Integer.parse(to_string(index_param)) do
      {index, ""} when index >= 0 ->
        transforms
        |> Enum.with_index()
        |> Enum.reject(fn {_item, i} -> i == index end)
        |> Enum.map(fn {item, _i} -> item end)

      _ ->
        transforms
    end
  end

  defp insert_transform_after_stage(transforms, stage_index_param, transform) do
    max_stage_index = max(length(transforms), 0)

    stage_index =
      case Integer.parse(to_string(stage_index_param)) do
        {parsed, ""} -> min(max(parsed, 0), max_stage_index)
        _ -> max_stage_index
      end

    insert_index = min(max(stage_index + 1, 0), length(transforms))
    List.insert_at(transforms, insert_index, transform)
  end

  defp parse_stage_index(stage_index_param, stage_progressions) do
    max_stage_index = max(length(stage_progressions) - 1, 0)

    case Integer.parse(to_string(stage_index_param)) do
      {parsed, ""} -> min(max(parsed, 0), max_stage_index)
      _ -> max_stage_index
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp move_item_by_position(items, position, delta) when is_list(items) do
    target = position + delta

    if position >= 0 and position < length(items) and target >= 0 and target < length(items) do
      value = Enum.at(items, position)

      items
      |> List.delete_at(position)
      |> List.insert_at(target, value)
    else
      items
    end
  end

  defp normalize_reorder_order(order, chord_count)
       when is_integer(chord_count) and chord_count >= 0 do
    base =
      case order do
        value when is_list(value) ->
          value
          |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 < chord_count))
          |> Enum.reduce([], fn index, acc -> if index in acc, do: acc, else: acc ++ [index] end)

        _ ->
          []
      end

    missing =
      if chord_count > 0 do
        Enum.to_list(0..(chord_count - 1))
      else
        []
      end
      |> Enum.reject(&(&1 in base))

    base ++ missing
  end

  defp normalize_deleted_indices(indices, chord_count)
       when is_integer(chord_count) and chord_count >= 0 do
    case indices do
      value when is_list(value) ->
        value
        |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 < chord_count))
        |> Enum.uniq()
        |> Enum.sort()

      _ ->
        []
    end
  end

  defp reorder_cards_for_order(cards, order) when is_list(cards) and is_list(order) do
    card_by_index = Map.new(cards, fn card -> {card.index, card} end)

    order
    |> Enum.map(&Map.get(card_by_index, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp reorder_cards_for_order(_cards, _order), do: []

  defp update_transform_opts(transforms, index_param, updater) do
    case Integer.parse(to_string(index_param)) do
      {target_index, ""} when target_index >= 0 ->
        transforms
        |> Enum.with_index()
        |> Enum.map(fn {transform, index} ->
          if index == target_index do
            %{transform | opts: updater.(transform.opts)}
          else
            transform
          end
        end)

      _ ->
        transforms
    end
  end

  defp parse_tonic(value) when is_binary(value) do
    case Map.get(@pitch_class_from_param, value) do
      nil -> {:error, "invalid tonic"}
      tonic -> {:ok, tonic}
    end
  end

  defp parse_tonic(_value), do: {:error, "invalid tonic"}

  defp parse_family(value, families) when is_binary(value) and is_list(families) do
    case Enum.find(families, &(Atom.to_string(&1.id) == value)) do
      %{id: id} -> {:ok, id}
      nil -> {:error, "invalid family"}
    end
  end

  defp parse_family(_value, _families), do: {:error, "invalid family"}

  defp parse_scale_mode(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_scale_mode(value) when is_binary(value) do
    case Integer.parse(value) do
      {mode, ""} when mode > 0 -> {:ok, mode}
      _ -> {:error, "invalid scale mode"}
    end
  end

  defp parse_scale_mode(_value), do: {:error, "invalid scale mode"}

  defp parse_strategy(value, strategies) when is_binary(value) and is_list(strategies) do
    case Enum.find(strategies, &(Atom.to_string(&1.id) == value)) do
      %{id: id} -> {:ok, id}
      nil -> {:error, "invalid strategy"}
    end
  end

  defp parse_strategy(_value, _strategies), do: {:error, "invalid strategy"}

  defp parse_shape_for_strategy(shape_value, selected_strategy, strategies) do
    with {:ok, shape} <- parse_shape(shape_value),
         {:ok, allowed_shapes} <- strategy_shapes(selected_strategy, strategies) do
      if shape in allowed_shapes do
        {:ok, shape}
      else
        {:error, "invalid shape for strategy"}
      end
    end
  end

  defp parse_shape(value) when is_binary(value) do
    case Enum.find(@shape_order, &(Atom.to_string(&1) == value)) do
      nil -> {:error, "invalid shape"}
      shape -> {:ok, shape}
    end
  end

  defp parse_shape(_value), do: {:error, "invalid shape"}

  defp source_scale_family_options(families, source) do
    selected_family = Map.get(source.opts, "family", "major")

    Enum.map(families, fn family ->
      %{
        value: Atom.to_string(family.id),
        label: family.name,
        selected: Atom.to_string(family.id) == selected_family
      }
    end)
  end

  defp source_scale_mode_options(families, source) do
    selected_family = Map.get(source.opts, "family", "major")
    selected_mode = Map.get(source.opts, "scale_mode", "1")

    case Enum.find(families, &(Atom.to_string(&1.id) == selected_family)) do
      %{mode_names: mode_names} when is_map(mode_names) and map_size(mode_names) > 0 ->
        mode_names
        |> Enum.sort_by(fn {mode_idx, _name} -> mode_idx end)
        |> Enum.map(fn {mode_idx, mode_name} ->
          mode_value = Integer.to_string(mode_idx)

          %{
            value: mode_value,
            label: "#{mode_idx} — #{mode_name}",
            selected: mode_value == selected_mode
          }
        end)

      _ ->
        []
    end
  end

  defp source_strategy_options(strategies, source) do
    selected_strategy = Map.get(source.opts, "strategy", "tertian")

    Enum.map(strategies, fn strategy ->
      %{
        value: Atom.to_string(strategy.id),
        label: strategy.label,
        selected: Atom.to_string(strategy.id) == selected_strategy
      }
    end)
  end

  defp source_shape_options(strategies, source) do
    selected_strategy = Map.get(source.opts, "strategy", "tertian")
    selected_shape = Map.get(source.opts, "shape", "triad")

    case Enum.find(strategies, &(Atom.to_string(&1.id) == selected_strategy)) do
      nil ->
        []

      strategy ->
        strategy.shapes
        |> order_shapes()
        |> Enum.map(fn shape ->
          %{
            value: Atom.to_string(shape),
            label: chord_kind_label(shape),
            selected: Atom.to_string(shape) == selected_shape
          }
        end)
    end
  end

  defp strategy_shapes(selected_strategy, strategies) when is_binary(selected_strategy) do
    case Enum.find(strategies, &(Atom.to_string(&1.id) == selected_strategy)) do
      nil -> {:error, "invalid strategy"}
      strategy -> {:ok, Map.get(strategy, :shapes, [])}
    end
  end

  defp strategy_shapes(_selected_strategy, _strategies), do: {:error, "invalid strategy"}

  defp default_mode_for_family(families, family_id) do
    case Enum.find(families, &(&1.id == family_id)) do
      %{mode_names: mode_names} when is_map(mode_names) and map_size(mode_names) > 0 ->
        mode_names
        |> Map.keys()
        |> Enum.sort()
        |> List.first()
        |> Integer.to_string()

      _ ->
        "1"
    end
  end

  defp default_shape_for_strategy(selected_strategy, strategies) do
    case Enum.find(strategies, &(Atom.to_string(&1.id) == selected_strategy)) do
      %{shapes: shapes} ->
        shape =
          shapes
          |> order_shapes()
          |> List.first()

        Atom.to_string(shape)

      _ ->
        "triad"
    end
  end

  defp order_shapes(shapes) when is_list(shapes) do
    Enum.sort_by(shapes, fn shape ->
      Enum.find_index(@shape_order, &(&1 == shape)) || 999
    end)
  end

  defp parse_quality(value) when is_binary(value) do
    case Map.get(@quality_from_param, value) do
      nil -> {:error, "invalid quality"}
      quality -> {:ok, quality}
    end
  end

  defp parse_quality(_value), do: {:error, "invalid quality"}

  defp parse_integer(value, _field_name) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, field_name) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "#{field_name} must be an integer"}
    end
  end

  defp parse_integer(_value, field_name), do: {:error, "#{field_name} must be an integer"}

  defp parse_optional_integer(value, _field_name) when value in [nil, ""], do: {:ok, nil}
  defp parse_optional_integer(value, field_name), do: parse_integer(value, field_name)

  defp parse_voicing_type("close"), do: {:ok, :close}
  defp parse_voicing_type("open"), do: {:ok, :open}
  defp parse_voicing_type(_), do: {:error, "invalid voicing_type"}

  defp parse_doubling("auto"), do: {:ok, :auto}
  defp parse_doubling("root"), do: {:ok, :root}
  defp parse_doubling("top"), do: {:ok, :top}
  defp parse_doubling("third"), do: {:ok, :third}
  defp parse_doubling("fifth"), do: {:ok, :fifth}
  defp parse_doubling("guide_tones"), do: {:ok, :guide_tones}
  defp parse_doubling("bass"), do: {:ok, :bass}
  defp parse_doubling(_), do: {:error, "invalid doubling"}

  defp parse_inversion_resolution_mode("per_step_centered"), do: {:ok, :per_step_centered}

  defp parse_inversion_resolution_mode("anchor_then_wander"),
    do: {:ok, :anchor_then_wander}

  defp parse_inversion_resolution_mode(_), do: {:error, "invalid inversion_resolution_mode"}

  defp append_chord_spec_from_opts(opts) when is_map(opts) do
    with {:ok, tonic} <- parse_tonic(Map.get(opts, "tonic")),
         {:ok, quality} <- parse_quality(Map.get(opts, "quality")),
         {:ok, octave} <- parse_integer(Map.get(opts, "octave"), "octave"),
         {:ok, inversion} <- parse_integer(Map.get(opts, "inversion"), "inversion"),
         {:ok, voicing_type} <- parse_voicing_type(Map.get(opts, "voicing_type")),
         {:ok, center_note} <- parse_integer(Map.get(opts, "center_note"), "center_note"),
         {:ok, range_min} <- parse_optional_integer(Map.get(opts, "range_min"), "range_min"),
         {:ok, range_max} <- parse_optional_integer(Map.get(opts, "range_max"), "range_max"),
         {:ok, voice_count} <- parse_optional_integer(Map.get(opts, "voice_count"), "voice_count"),
         {:ok, doubling} <- parse_doubling(Map.get(opts, "doubling")),
         {:ok, inversion_resolution_mode} <-
           parse_inversion_resolution_mode(Map.get(opts, "inversion_resolution_mode")),
         {:ok, chord_spec} <-
           ChordSpec.new(%{
             harmonic_identity: %ChordSpec.HarmonicIdentity{root: tonic, quality: quality},
             octave: octave,
             inversion: inversion,
             voicing: %ChordSpec.Voicing{
               type: voicing_type,
               center_note: center_note,
               range_min: range_min,
               range_max: range_max,
               voice_count: voice_count,
               doubling: doubling,
               inversion_resolution_mode: inversion_resolution_mode
             }
           }) do
      {:ok, chord_spec}
    end
  end

  defp append_chord_spec_from_opts(_), do: {:error, :invalid_append_opts}

  defp append_chord_preview(opts) do
    with {:ok, chord_spec} <- append_chord_spec_from_opts(opts) do
      notes = Resolver.resolve(chord_spec)

      %{
        symbol: ChordSpec.symbol_label(chord_spec),
        named_notes: join_named_notes(notes),
        keyboard_keys: piano_keys(notes)
      }
    else
      _ -> nil
    end
  end

  defp chord_kind_label(:triad), do: "Triad"
  defp chord_kind_label(:seventh), do: "Seventh"
  defp chord_kind_label(:add6), do: "Add 6"
  defp chord_kind_label(:six_nine), do: "6/9"
  defp chord_kind_label(:ninth), do: "9th"
  defp chord_kind_label(:eleventh), do: "11th"
  defp chord_kind_label(:thirteenth), do: "13th"

  defp selected_tonic_keyboard_key(%{opts: opts}) do
    case Map.get(opts, "tonic", "c") do
      "c_sharp" -> "d_flat"
      "d_sharp" -> "e_flat"
      "f_sharp" -> "g_flat"
      "g_sharp" -> "a_flat"
      "a_sharp" -> "b_flat"
      tonic -> tonic
    end
  end

  defp degree_label(degree) do
    case degree do
      1 -> "I"
      2 -> "II"
      3 -> "III"
      4 -> "IV"
      5 -> "V"
      6 -> "VI"
      7 -> "VII"
      _ -> Integer.to_string(degree)
    end
  end

  defp build_stage_cards(stage_progressions) when is_list(stage_progressions) do
    stage_progressions
    |> Enum.with_index()
    |> Enum.map(fn {progression, index} ->
      chords = if is_struct(progression, ChordProgression), do: progression.chords, else: []

      %{
        index: index,
        chord_cards: build_chord_cards(chords)
      }
    end)
  end

  defp build_stage_cards(_), do: []

  defp build_chord_cards(chords) when is_list(chords) do
    chords
    |> Enum.with_index()
    |> Enum.map(fn {chord_spec, index} ->
      notes = Resolver.resolve(chord_spec)

      %{
        index: index,
        degree: degree_label(index + 1),
        symbol: ChordSpec.symbol_label(chord_spec),
        named_notes: join_named_notes(notes),
        keyboard_keys: piano_keys(notes)
      }
    end)
  end

  defp build_chord_cards(_chords), do: []

  defp join_named_notes(notes) do
    notes
    |> Enum.map(fn note ->
      {name, octave} = ChordSpec.note_name(note)
      "#{ChordSpec.root_label(name)}#{octave}"
    end)
    |> Enum.join("  ")
  end

  defp piano_keys(active_notes) when is_list(active_notes) do
    FullPianoKeyboard.key_maps(active_notes: active_notes)
  end

  defp piano_keys(_active_notes), do: []

  defp toggle_button_classes(true) do
    "rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
  end

  defp toggle_button_classes(false) do
    "rounded-sm border border-zinc-700 bg-zinc-900/80 px-3 py-1.5 font-mono text-xs text-zinc-200 transition-colors duration-150 hover:border-zinc-500"
  end

  defp format_error({:source_failed, reason}), do: "Source failed: #{inspect(reason)}"

  defp format_error({:transform_failed, index, reason}) do
    "Transform step #{index + 1} failed: #{inspect(reason)}"
  end

  defp format_error(other), do: inspect(other)

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
end
