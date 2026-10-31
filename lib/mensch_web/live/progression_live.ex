defmodule MenschWeb.ProgressionLive do
  use MenschWeb, :live_view

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Progression
  alias Mensch.Harmony.Progression.Middleware.EnsureBassAscending
  alias Mensch.Harmony.Progression.Middleware.TransposeAll
  alias Mensch.Harmony.Progression.Source.CreateWithFixedChord
  alias Mensch.Harmony.Progression.Source.CreateWithScaleGeneratedHarmonicIdentities
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

  @source_ids ["scale_generated_harmonic_identities", "fixed_chord"]
  @transform_ids ["ensure_bass_ascending", "transpose_all"]

  @qualities ChordSpec.qualities() |> Enum.sort()

  @pitch_class_from_param Map.new(@pitch_classes, fn pitch_class ->
                            {Atom.to_string(pitch_class), pitch_class}
                          end)

  @quality_from_param Map.new(@qualities, fn quality ->
                        {Atom.to_string(quality), quality}
                      end)

  @shape_order [:triad, :seventh, :ninth, :eleventh, :thirteenth, :add6, :six_nine]

  @impl true
  def mount(_params, _session, socket) do
    source = default_source_config()

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:scale_families, ScaleRegistry.all())
      |> assign(:chord_strategies, Scale.chord_strategy_options())
      |> assign(:source, source)
      |> assign(:transforms, [])
      |> assign(:next_transform_id, hd(@transform_ids))
      |> assign(:chords, [])
      |> assign(:preview_note_channels, [])
      |> assign(:preview_stop_ref, nil)
      |> assign(:error_message, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_source_id", params, socket) do
    source_id =
      params["source_id"] ||
        get_in(params, ["source", "source_id"]) ||
        params["value"]

    source =
      if source_id in @source_ids do
        default_source_config(source_id)
      else
        socket.assigns.source
      end

    {:noreply,
     socket
     |> assign(:source, source)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("set_source_tonic", %{"pitch_class" => tonic}, socket) do
    source =
      update_source_opts(socket.assigns.source, fn opts ->
        if Map.has_key?(@pitch_class_from_param, tonic),
          do: Map.put(opts, "tonic", tonic),
          else: opts
      end)

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_source_family", %{"family" => family}, socket) do
    source =
      update_source_opts(socket.assigns.source, fn opts ->
        case parse_family(family, socket.assigns.scale_families) do
          {:ok, family_id} ->
            mode = default_mode_for_family(socket.assigns.scale_families, family_id)
            opts |> Map.put("family", family) |> Map.put("scale_mode", mode)

          {:error, _reason} ->
            opts
        end
      end)

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_source_scale_mode", %{"scale_mode" => scale_mode}, socket) do
    source =
      update_source_opts(socket.assigns.source, fn opts ->
        case parse_positive_integer(scale_mode) do
          {:ok, _mode} -> Map.put(opts, "scale_mode", scale_mode)
          {:error, _reason} -> opts
        end
      end)

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_source_strategy", %{"strategy" => strategy}, socket) do
    source =
      update_source_opts(socket.assigns.source, fn opts ->
        case parse_strategy(strategy, socket.assigns.chord_strategies) do
          {:ok, _strategy} ->
            shape = default_shape_for_strategy(strategy, socket.assigns.chord_strategies)
            opts |> Map.put("strategy", strategy) |> Map.put("shape", shape)

          {:error, _reason} ->
            opts
        end
      end)

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_source_shape", %{"shape" => shape}, socket) do
    source =
      update_source_opts(socket.assigns.source, fn opts ->
        strategy = Map.get(opts, "strategy")

        case parse_shape_for_strategy(shape, strategy, socket.assigns.chord_strategies) do
          {:ok, _shape} -> Map.put(opts, "shape", shape)
          {:error, _reason} -> opts
        end
      end)

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_source_quality", %{"quality" => quality}, socket) do
    source =
      update_source_opts(socket.assigns.source, fn opts ->
        if Map.has_key?(@quality_from_param, quality),
          do: Map.put(opts, "quality", quality),
          else: opts
      end)

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_source_field", %{"field" => field, "value" => value}, socket) do
    source =
      case field do
        "count" ->
          update_source_integer(socket.assigns.source, "count", value)

        "octave" ->
          update_source_integer(socket.assigns.source, "octave", value)

        "inversion" ->
          update_source_integer(socket.assigns.source, "inversion", value)

        _ ->
          socket.assigns.source
      end

    {:noreply, assign(socket, :source, source)}
  end

  @impl true
  def handle_event("set_next_transform", params, socket) do
    transform_id =
      params["transform_id"] ||
        get_in(params, ["transform", "transform_id"]) ||
        params["value"]

    value =
      if transform_id in @transform_ids, do: transform_id, else: socket.assigns.next_transform_id

    {:noreply, assign(socket, :next_transform_id, value)}
  end

  @impl true
  def handle_event("add_transform", _params, socket) do
    transform = default_transform_config(socket.assigns.next_transform_id)

    {:noreply,
     socket
     |> assign(:transforms, socket.assigns.transforms ++ [transform])
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("remove_transform", %{"index" => index}, socket) do
    transforms = remove_transform_by_index(socket.assigns.transforms, index)
    {:noreply, socket |> assign(:transforms, transforms) |> assign(:error_message, nil)}
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

    {:noreply, assign(socket, :transforms, transforms)}
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

    {:noreply, assign(socket, :transforms, transforms)}
  end

  @impl true
  def handle_event("run_pipeline", _params, socket) do
    {:noreply, run_pipeline(socket)}
  end

  @impl true
  def handle_event("play_chord", %{"index" => index}, socket) do
    chord =
      case Integer.parse(to_string(index)) do
        {parsed, ""} -> Enum.at(socket.assigns.chords, parsed)
        _ -> nil
      end

    case chord do
      %ChordSpec{} = chord_spec ->
        notes = Resolver.resolve(chord_spec)
        play_notes_for_3s(socket, notes)

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid chord selection")}
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
      |> assign(:source_label, source_label(assigns.source.id))
      |> assign(:selected_tonic_keyboard_key, selected_tonic_keyboard_key(assigns.source))
      |> assign(
        :scale_family_options,
        source_scale_family_options(assigns.scale_families, assigns.source)
      )
      |> assign(
        :scale_mode_options,
        source_scale_mode_options(assigns.scale_families, assigns.source)
      )
      |> assign(
        :strategy_options,
        source_strategy_options(assigns.chord_strategies, assigns.source)
      )
      |> assign(:shape_options, source_shape_options(assigns.chord_strategies, assigns.source))
      |> assign(:chord_cards, build_chord_cards(assigns.chords))

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:progression}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Chord Progression Lab"
          subtitle="Build a progression pipeline with one source and append-only transforms."
        />

        <div class="ui-radius-table space-y-4 border border-zinc-700/60 bg-black/30 p-4">
          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">Source</h3>

            <div class="space-y-1">
              <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Source Type
              </label>
              <form phx-change="set_source_id">
                <select
                  class="w-full max-w-sm rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                  name="source_id"
                >
                  <option :for={id <- source_ids()} value={id} selected={@source.id == id}>
                    {source_label(id)}
                  </option>
                </select>
              </form>
            </div>

            <p class="font-mono text-xs text-zinc-300">Current: {@source_label}</p>

            <%= if @source.id == "scale_generated_harmonic_identities" do %>
              <div class="space-y-3 rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  1) Define Scale
                </h3>

                <div class="max-w-xl">
                  <MenschWeb.PitchClassKeyboard.mini
                    id="progression-scale-source-tonic"
                    label="Tonic"
                    event="set_source_tonic"
                    selected_key={@selected_tonic_keyboard_key}
                    selected_key_color="#f6d365"
                  />
                </div>

                <div class="grid gap-3 md:grid-cols-2">
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                      Scale Family
                    </span>
                    <form id="progression-scale-source-family-form" phx-change="set_source_family">
                      <select
                        name="family"
                        class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                      >
                        <option
                          :for={item <- @scale_family_options}
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
                    <%= if @scale_mode_options == [] do %>
                      <div class="rounded-sm border border-zinc-800 bg-zinc-950/70 px-2 py-1.5 font-mono text-xs text-zinc-500">
                        No mode (standalone scale)
                      </div>
                    <% else %>
                      <form id="progression-scale-source-mode-form" phx-change="set_source_scale_mode">
                        <select
                          name="scale_mode"
                          class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                        >
                          <option
                            :for={item <- @scale_mode_options}
                            value={item.value}
                            selected={item.selected}
                          >
                            {item.label}
                          </option>
                        </select>
                      </form>
                    <% end %>
                  </label>
                </div>
              </div>

              <div class="space-y-3 rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  2) Chord Strategy
                </h3>

                <div class="grid gap-3 md:grid-cols-2">
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                      Strategy
                    </span>
                    <form id="progression-scale-source-strategy-form" phx-change="set_source_strategy">
                      <select
                        name="strategy"
                        class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                      >
                        <option
                          :for={item <- @strategy_options}
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
                    <form id="progression-scale-source-shape-form" phx-change="set_source_shape">
                      <select
                        name="shape"
                        class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                      >
                        <option
                          :for={item <- @shape_options}
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

            <%= if @source.id == "fixed_chord" do %>
              <div class="space-y-3 rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3">
                <div class="space-y-1">
                  <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Root
                  </label>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={root <- pitch_classes()}
                      type="button"
                      phx-click="set_source_tonic"
                      phx-value-pitch_class={Atom.to_string(root)}
                      class={toggle_button_classes(@source.opts["tonic"] == Atom.to_string(root))}
                    >
                      {ChordSpec.root_label(root)}
                    </button>
                  </div>
                </div>

                <div class="space-y-1">
                  <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Quality
                  </label>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={quality <- qualities()}
                      type="button"
                      phx-click="set_source_quality"
                      phx-value-quality={Atom.to_string(quality)}
                      class={
                        toggle_button_classes(@source.opts["quality"] == Atom.to_string(quality))
                      }
                    >
                      {Atom.to_string(quality)}
                    </button>
                  </div>
                </div>

                <div class="grid gap-3 md:grid-cols-3">
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                      Count
                    </span>
                    <input
                      type="number"
                      min="1"
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                      value={@source.opts["count"]}
                      phx-blur="set_source_field"
                      phx-value-field="count"
                    />
                  </label>

                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                      Octave
                    </span>
                    <input
                      type="number"
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                      value={@source.opts["octave"]}
                      phx-blur="set_source_field"
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
                      value={@source.opts["inversion"]}
                      phx-blur="set_source_field"
                      phx-value-field="inversion"
                    />
                  </label>
                </div>
              </div>
            <% end %>
          </div>

          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">Transforms</h3>

            <div class="flex flex-wrap items-end gap-2">
              <label class="space-y-1">
                <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Add Transform
                </span>
                <form phx-change="set_next_transform">
                  <select
                    class="w-64 rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                    name="transform_id"
                  >
                    <option
                      :for={id <- transform_ids()}
                      value={id}
                      selected={@next_transform_id == id}
                    >
                      {transform_label(id)}
                    </option>
                  </select>
                </form>
              </label>

              <button
                type="button"
                phx-click="add_transform"
                class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
              >
                Add
              </button>
            </div>

            <div class="space-y-3">
              <div
                :for={{transform, index} <- Enum.with_index(@transforms)}
                class="rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3"
              >
                <div class="mb-2 flex items-center justify-between">
                  <p class="font-mono text-xs text-zinc-200">
                    Step {index + 1}: {transform_label(transform.id)}
                  </p>
                  <button
                    type="button"
                    phx-click="remove_transform"
                    phx-value-index={index}
                    class="rounded-sm border border-rose-500/50 bg-rose-900/20 px-2 py-1 font-mono text-[11px] text-rose-200 transition-colors duration-150 hover:bg-rose-900/40"
                  >
                    Remove
                  </button>
                </div>

                <%= if transform.id == "ensure_bass_ascending" do %>
                  <label class="inline-flex items-center gap-2 font-mono text-xs text-zinc-200">
                    <input
                      type="checkbox"
                      checked={transform.opts["include_foreign_bass"]}
                      phx-click="set_transform_bool"
                      phx-value-index={index}
                      phx-value-field="include_foreign_bass"
                      phx-value-value={
                        if(transform.opts["include_foreign_bass"], do: "false", else: "true")
                      }
                    /> Include foreign bass
                  </label>
                <% end %>

                <%= if transform.id == "transpose_all" do %>
                  <label class="space-y-1">
                    <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                      Semitones
                    </span>
                    <input
                      type="number"
                      step="1"
                      class="w-full max-w-xs rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                      value={transform.opts["semitones"]}
                      phx-blur="set_transform_integer"
                      phx-value-index={index}
                      phx-value-field="semitones"
                    />
                  </label>
                <% end %>
              </div>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="run_pipeline"
              class="rounded-sm border border-emerald-300 bg-emerald-400/20 px-4 py-2 font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
            >
              Run Pipeline
            </button>
          </div>

          <div :if={@error_message} class="rounded-sm border border-rose-500/40 bg-rose-950/30 p-3">
            <p class="font-mono text-xs text-rose-200">{@error_message}</p>
          </div>

          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3">
            <h3 class="mb-2 font-mono text-[11px] uppercase tracking-wide text-zinc-400">
              Chords List
            </h3>
            <div class="space-y-4">
              <div
                :for={card <- @chord_cards}
                class="rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-3"
              >
                <div class="flex flex-col gap-3 md:flex-row md:items-start">
                  <button
                    type="button"
                    phx-click="play_chord"
                    phx-value-index={card.index}
                    class="w-56 shrink-0 rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-2 text-center font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
                  >
                    {card.degree} · {card.symbol}
                  </button>

                  <div class="min-w-0 flex-1 md:max-w-4xl">
                    <div class="rounded-md border border-zinc-700/70 bg-zinc-950 p-2">
                      <FullPianoKeyboard.keyboard
                        id={"progression-keyboard-#{card.index}"}
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
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp run_pipeline(socket) do
    with {:ok, source_fn} <- source_to_fun(socket.assigns.source),
         {:ok, transforms} <- transforms_to_funs(socket.assigns.transforms),
         {:ok, progression} <- Progression.run_with_source(source_fn, transforms) do
      socket
      |> assign(:chords, progression.chords)
      |> assign(:error_message, nil)
    else
      {:error, reason} ->
        socket
        |> assign(:chords, [])
        |> assign(:error_message, format_error(reason))
    end
  end

  defp source_to_fun(%{id: "fixed_chord", opts: opts}) do
    with {:ok, tonic} <- parse_tonic(Map.get(opts, "tonic")),
         {:ok, quality} <- parse_quality(Map.get(opts, "quality")),
         {:ok, count} <- parse_integer(Map.get(opts, "count"), "count"),
         {:ok, octave} <- parse_integer(Map.get(opts, "octave"), "octave"),
         {:ok, inversion} <- parse_integer(Map.get(opts, "inversion"), "inversion") do
      source =
        CreateWithFixedChord.source(
          root: tonic,
          quality: quality,
          count: count,
          octave: octave,
          inversion: inversion
        )

      {:ok, source}
    end
  end

  defp source_to_fun(%{id: "scale_generated_harmonic_identities", opts: opts}) do
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
      source =
        CreateWithScaleGeneratedHarmonicIdentities.source(
          scale: %{tonic: tonic, family: family, mode: mode},
          strategy: strategy,
          shape: shape,
          spelling_mode: :practical,
          render_defaults: %{octave: 3, inversion: 0}
        )

      {:ok, source}
    end
  end

  defp source_to_fun(_), do: {:error, :invalid_source}

  defp transforms_to_funs(transforms) when is_list(transforms) do
    transforms
    |> Enum.reduce_while({:ok, []}, fn transform, {:ok, acc} ->
      case transform_to_fun(transform) do
        {:ok, fun} -> {:cont, {:ok, acc ++ [fun]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp transform_to_fun(%{id: "ensure_bass_ascending", opts: opts}) do
    include_foreign_bass = Map.get(opts, "include_foreign_bass", false)
    {:ok, EnsureBassAscending.middleware(include_foreign_bass: include_foreign_bass)}
  end

  defp transform_to_fun(%{id: "transpose_all", opts: opts}) do
    with {:ok, semitones} <- parse_integer(Map.get(opts, "semitones"), "semitones") do
      {:ok, TransposeAll.middleware(semitones: semitones)}
    end
  end

  defp transform_to_fun(_), do: {:error, :invalid_transform}

  defp source_ids, do: @source_ids
  defp transform_ids, do: @transform_ids
  defp qualities, do: @qualities
  defp pitch_classes, do: @pitch_classes

  defp source_label("scale_generated_harmonic_identities"),
    do: "Create With Scale-Generated Harmonic Identities"

  defp source_label("fixed_chord"), do: "Create With Fixed Chord (Test)"
  defp source_label(_), do: "Unknown Source"

  defp transform_label("ensure_bass_ascending"), do: "Ensure Bass Ascending"
  defp transform_label("transpose_all"), do: "Transpose All"
  defp transform_label(_), do: "Unknown Transform"

  defp default_source_config(), do: default_source_config("scale_generated_harmonic_identities")

  defp default_source_config("fixed_chord") do
    %{
      id: "fixed_chord",
      opts: %{"tonic" => "c", "quality" => "maj", "count" => 7, "octave" => 3, "inversion" => 0}
    }
  end

  defp default_source_config("scale_generated_harmonic_identities") do
    %{
      id: "scale_generated_harmonic_identities",
      opts: %{
        "tonic" => "c",
        "family" => "major",
        "scale_mode" => "1",
        "strategy" => "tertian",
        "shape" => "triad"
      }
    }
  end

  defp default_source_config(_), do: default_source_config("scale_generated_harmonic_identities")

  defp default_transform_config("ensure_bass_ascending") do
    %{id: "ensure_bass_ascending", opts: %{"include_foreign_bass" => false}}
  end

  defp default_transform_config("transpose_all") do
    %{id: "transpose_all", opts: %{"semitones" => 12}}
  end

  defp default_transform_config(_), do: default_transform_config("ensure_bass_ascending")

  defp update_source_opts(source, updater) do
    %{source | opts: updater.(source.opts)}
  end

  defp update_source_integer(source, field, value) do
    update_source_opts(source, fn opts ->
      case parse_integer(value, field) do
        {:ok, parsed} -> Map.put(opts, field, parsed)
        {:error, _reason} -> opts
      end
    end)
  end

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

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} when num > 0 -> {:ok, num}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_integer}

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
