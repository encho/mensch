defmodule MenschWeb.ScaleChordLabLive do
  use MenschWeb, :live_view

  alias Mensch.Scale
  alias Mensch.Scale.ScaleRegistry
  alias Mensch.Scale.ScaleSpec
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.HarmonicIdentityInference
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

  @impl true
  def mount(_params, _session, socket) do
    families = ScaleRegistry.all()
    default_tonic = :c
    default_family = :major
    default_mode = 1
    default_strategy = :tertian
    default_shape = :triad

    socket =
      socket
      |> assign(:midi_status, Mensch.Midi.Connection.status())
      |> assign(:families, families)
      |> assign(:strategies, Scale.chord_strategy_options())
      |> assign(:selected_tonic, Atom.to_string(default_tonic))
      |> assign(:selected_family, Atom.to_string(default_family))
      |> assign(:selected_mode, Integer.to_string(default_mode))
      |> assign(:selected_strategy, Atom.to_string(default_strategy))
      |> assign(:selected_shape, Atom.to_string(default_shape))
      |> assign(:selected_degree, "1")
      |> assign(:scale_spec, nil)
      |> assign(:scale_notes, [])
      |> assign(:generated_chord, nil)
      |> assign(:resolved_harmonic_identities, [])
      |> assign(:keyboard_notes, [])
      |> assign(:tonic_keyboard_notes, [])
      |> assign(:error_message, nil)
      |> recompute()

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
     |> recompute()}
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
     |> assign(:selected_degree, "1")
     |> recompute()}
  end

  @impl true
  def handle_event("set_mode", params, socket) do
    mode = params["mode"] || ""

    {:noreply,
     socket
     |> assign(:selected_mode, mode)
     |> assign(:selected_degree, "1")
     |> recompute()}
  end

  @impl true
  def handle_event("set_strategy", params, socket) do
    strategy = params["strategy"] || socket.assigns.selected_strategy
    shape = default_shape_for_strategy(strategy, socket.assigns.strategies)

    {:noreply,
     socket
     |> assign(:selected_strategy, strategy)
     |> assign(:selected_shape, shape)
     |> recompute()}
  end

  @impl true
  def handle_event("set_shape", params, socket) do
    shape = params["shape"] || socket.assigns.selected_shape

    {:noreply,
     socket
     |> assign(:selected_shape, shape)
     |> recompute()}
  end

  @impl true
  def handle_event("set_degree", params, socket) do
    degree = params["degree"] || "1"

    {:noreply,
     socket
     |> assign(:selected_degree, degree)
     |> recompute()}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:family_options, family_options(assigns.families, assigns.selected_family))
      |> assign(
        :mode_options,
        mode_options(assigns.families, assigns.selected_family, assigns.selected_mode)
      )
      |> assign(
        :shape_options,
        shape_options(assigns.strategies, assigns.selected_strategy, assigns.selected_shape)
      )
      |> assign(:degree_options, degree_options(assigns.scale_spec, assigns.selected_degree))
      |> assign(
        :strategy_options,
        strategy_options(assigns.strategies, assigns.selected_strategy)
      )
      |> assign(
        :keyboard_keys,
        keyboard_keys(assigns.keyboard_notes, assigns.tonic_keyboard_notes)
      )

    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:scale_chord_lab}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Scale Chord Lab"
          subtitle="Define a scale, choose a strategy and degree, and inspect generated chord tones."
        />

        <div class="ui-radius-table space-y-4 border border-zinc-700/60 bg-black/30 p-4">
          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
              1) Define Scale
            </h3>

            <div class="max-w-xl">
              <MenschWeb.PitchClassKeyboard.mini
                id="scale-chord-lab-tonic"
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
                <form id="scale-chord-lab-family-form" phx-change="set_family">
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
                  <form id="scale-chord-lab-mode-form" phx-change="set_mode">
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

          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
              2) Chord Strategy
            </h3>

            <div class="grid gap-3 md:grid-cols-3">
              <label class="space-y-1">
                <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                  Strategy
                </span>
                <form id="scale-chord-lab-strategy-form" phx-change="set_strategy">
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
                <form id="scale-chord-lab-shape-form" phx-change="set_shape">
                  <select
                    name="shape"
                    class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1.5 font-mono text-xs text-zinc-100"
                  >
                    <option :for={item <- @shape_options} value={item.value} selected={item.selected}>
                      {item.label}
                    </option>
                  </select>
                </form>
              </label>
            </div>
          </div>

          <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-3">
            <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
              3) Select Degree
            </h3>

            <%= if @degree_options == [] do %>
              <p class="font-mono text-xs text-zinc-500">Choose a scale first.</p>
            <% else %>
              <div id="scale-chord-lab-degree-buttons" class="flex flex-wrap gap-2">
                <button
                  :for={item <- @degree_options}
                  type="button"
                  phx-click="set_degree"
                  phx-value-degree={item.value}
                  class={[
                    "rounded-sm border px-3 py-1.5 font-mono text-xs font-semibold transition-colors duration-150",
                    item.selected && "border-emerald-300 bg-emerald-400/20 text-emerald-100",
                    !item.selected &&
                      "border-zinc-700 bg-zinc-900/80 text-zinc-300 hover:border-zinc-500 hover:text-zinc-100"
                  ]}
                >
                  {item.label}
                </button>
              </div>
            <% end %>
          </div>

          <div :if={@error_message} class="rounded-sm border border-rose-500/40 bg-rose-950/30 p-3">
            <p class="font-mono text-xs text-rose-200">{@error_message}</p>
          </div>

          <%= if @scale_spec && @generated_chord do %>
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-2">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                4) Generated Chord
              </h3>
              <h3 class="font-mono text-sm text-zinc-100">
                {full_scale_name(@selected_tonic, @scale_spec)}
              </h3>
              <p class="font-mono text-xs text-zinc-300">Scale: {Enum.join(@scale_notes, "  ")}</p>
              <p class="font-mono text-xs text-zinc-300">
                Chord: {Enum.join(@generated_chord.note_names, "  ")}
              </p>
              <p class="font-mono text-xs text-zinc-500">
                Root: {@generated_chord.root_note} · Degree: {@generated_chord.degree} · Shape: {shape_label(
                  @generated_chord.shape
                )}
              </p>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-2">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                Piano Keyboard
              </h3>

              <FullPianoKeyboard.keyboard
                id="scale-chord-lab-full-keyboard"
                keys={@keyboard_keys}
                height_class="h-40"
                show_bottom_lane={false}
                color_mode={:dark}
              />

              <p class="font-mono text-[11px] text-zinc-400">
                Yellow notes mark chord root across octaves. Green notes are other chord tones.
              </p>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/40 p-3 space-y-2">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                5) Resolved Harmonic Identities
              </h3>

              <div id="scale-chord-lab-resolved-identities" class="space-y-1">
                <div
                  :for={{match, idx} <- Enum.with_index(@resolved_harmonic_identities)}
                  class="rounded-sm border border-zinc-800 bg-zinc-900/60 px-2 py-1"
                >
                  <div class="flex items-center justify-between">
                    <p class="font-mono text-xs text-zinc-100">
                      {idx + 1}. {harmonic_identity_label(match, @generated_chord)}
                    </p>
                    <p class="font-mono text-[11px] text-zinc-300">
                      Source {identity_source_label(match)}
                    </p>
                  </div>
                  <div class="mt-1 flex items-center justify-between">
                    <p class="font-mono text-[11px] text-zinc-400">
                      {inspect(match.harmonic_identity)}
                    </p>
                    <p class="font-mono text-[11px] text-emerald-200">
                      Quality {format_quality(match.quality || 100.0)}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp recompute(socket) do
    with {:ok, tonic} <- parse_tonic(socket.assigns.selected_tonic),
         {:ok, family} <- parse_family(socket.assigns.selected_family),
         {:ok, mode} <-
           parse_mode_for_family(socket.assigns.families, family, socket.assigns.selected_mode),
         {:ok, scale_spec} <- Scale.build_scale(tonic, family, mode),
         {:ok, scale_notes} <- Scale.notes(scale_spec),
         {:ok, strategy} <- parse_strategy(socket.assigns.selected_strategy),
         {:ok, shape} <-
           parse_shape_for_strategy(
             socket.assigns.selected_shape,
             socket.assigns.selected_strategy,
             socket.assigns.strategies
           ),
         {:ok, degree} <- parse_degree(socket.assigns.selected_degree),
         {:ok, generated_chord} <-
           Scale.generate_chord(scale_spec, degree,
             strategy: strategy,
             shape: shape
           ),
         {:ok, keyboard_notes} <- single_chord_voicing_notes(generated_chord, 21, 108),
         resolved_harmonic_identities <-
           resolve_harmonic_identities(
             generated_chord,
             scale_spec,
             keyboard_notes,
             strategy,
             shape,
             degree
           ),
         {:ok, tonic_keyboard_notes} <- single_root_note(generated_chord, keyboard_notes) do
      socket
      |> assign(:scale_spec, scale_spec)
      |> assign(:scale_notes, scale_notes)
      |> assign(:generated_chord, generated_chord)
      |> assign(:resolved_harmonic_identities, resolved_harmonic_identities)
      |> assign(:keyboard_notes, keyboard_notes)
      |> assign(:tonic_keyboard_notes, tonic_keyboard_notes)
      |> assign(:error_message, nil)
    else
      {:error, reason} ->
        socket
        |> assign(:scale_spec, nil)
        |> assign(:scale_notes, [])
        |> assign(:generated_chord, nil)
        |> assign(:resolved_harmonic_identities, [])
        |> assign(:keyboard_notes, [])
        |> assign(:tonic_keyboard_notes, [])
        |> assign(:error_message, format_error(reason))
    end
  end

  defp single_chord_voicing_notes(%{pitch_classes: [root_pc | rest_pcs]}, min_note, max_note)
       when is_integer(min_note) and is_integer(max_note) do
    root_note = nearest_note_for_pitch_class(root_pc, 60)

    if root_note < min_note or root_note > max_note do
      {:error, :root_out_of_keyboard_range}
    else
      {notes_reversed, _last_note} =
        Enum.reduce(rest_pcs, {[root_note], root_note}, fn pitch_class, {acc, prev_note} ->
          next_note = next_note_for_pitch_class(pitch_class, prev_note)
          {[next_note | acc], next_note}
        end)

      notes =
        notes_reversed
        |> Enum.reverse()
        |> Enum.filter(&(&1 >= min_note and &1 <= max_note))

      {:ok, notes}
    end
  end

  defp single_chord_voicing_notes(_generated_chord, _min_note, _max_note),
    do: {:error, :invalid_pitch_classes}

  defp single_root_note(%{root_pitch_class: root_pc}, [first | _rest])
       when is_integer(root_pc) and is_integer(first) do
    root_note =
      if rem(first, 12) == root_pc do
        first
      else
        nearest_note_for_pitch_class(root_pc, first)
      end

    {:ok, [root_note]}
  end

  defp single_root_note(_generated_chord, _keyboard_notes), do: {:error, :invalid_root}

  defp nearest_note_for_pitch_class(pitch_class, reference_note) do
    ref_octave = div(reference_note, 12)

    candidates =
      for octave <- (ref_octave - 2)..(ref_octave + 2) do
        octave * 12 + pitch_class
      end

    Enum.min_by(candidates, &abs(&1 - reference_note))
  end

  defp next_note_for_pitch_class(pitch_class, prev_note) do
    octave = div(prev_note, 12)
    candidate = octave * 12 + pitch_class

    if candidate < prev_note do
      candidate + 12
    else
      candidate
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

  defp parse_strategy(value) when is_binary(value) do
    allowed = MapSet.new(Enum.map(Scale.chord_strategy_options(), &Atom.to_string(&1.id)))

    if MapSet.member?(allowed, value) do
      {:ok, String.to_atom(value)}
    else
      {:error, :invalid_strategy}
    end
  end

  defp parse_strategy(_), do: {:error, :invalid_strategy}

  defp parse_shape(value) when is_binary(value) do
    shape = String.to_atom(value)

    if shape in [:triad, :seventh, :ninth, :eleventh, :thirteenth, :add6, :six_nine] do
      {:ok, shape}
    else
      {:error, :invalid_shape}
    end
  end

  defp parse_shape(_), do: {:error, :invalid_shape}

  defp parse_shape_for_strategy(shape_value, selected_strategy, strategies) do
    with {:ok, shape} <- parse_shape(shape_value),
         {:ok, allowed_shapes} <- strategy_shapes(selected_strategy, strategies) do
      if shape in allowed_shapes do
        {:ok, shape}
      else
        {:error, {:invalid_shape_for_strategy, shape, String.to_atom(selected_strategy)}}
      end
    end
  end

  defp parse_degree(value) when is_binary(value) do
    case Integer.parse(value) do
      {degree, ""} when degree >= 1 -> {:ok, degree}
      _ -> {:error, :invalid_degree}
    end
  end

  defp parse_degree(_), do: {:error, :invalid_degree}

  defp find_family(families, family_string) do
    Enum.find(families, fn family -> Atom.to_string(family.id) == family_string end)
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

  defp strategy_options(strategies, selected_strategy) do
    Enum.map(strategies, fn strategy ->
      %{
        value: Atom.to_string(strategy.id),
        label: strategy.label,
        selected: Atom.to_string(strategy.id) == selected_strategy
      }
    end)
  end

  defp shape_options(strategies, selected_strategy, selected_shape) do
    case Enum.find(strategies, &(Atom.to_string(&1.id) == selected_strategy)) do
      nil ->
        []

      strategy ->
        strategy.shapes
        |> order_shapes()
        |> Enum.map(fn shape ->
          %{
            value: Atom.to_string(shape),
            label: shape_label(shape),
            selected: Atom.to_string(shape) == selected_shape
          }
        end)
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
    order = [:triad, :seventh, :ninth, :eleventh, :thirteenth, :add6, :six_nine]

    Enum.sort_by(shapes, fn shape ->
      Enum.find_index(order, &(&1 == shape)) || 999
    end)
  end

  defp strategy_shapes(selected_strategy, strategies) do
    case Enum.find(strategies, &(Atom.to_string(&1.id) == selected_strategy)) do
      nil -> {:error, :invalid_strategy}
      strategy -> {:ok, Map.get(strategy, :shapes, [])}
    end
  end

  defp degree_options(%ScaleSpec{intervals: intervals}, selected_degree) do
    intervals
    |> length()
    |> then(fn size ->
      Enum.map(1..size, fn degree ->
        value = Integer.to_string(degree)
        %{value: value, label: "#{degree}", selected: value == selected_degree}
      end)
    end)
  end

  defp degree_options(_scale_spec, _selected_degree), do: []

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

  defp shape_label(:triad), do: "Triad"
  defp shape_label(:seventh), do: "Seventh"
  defp shape_label(:ninth), do: "Ninth"
  defp shape_label(:eleventh), do: "Eleventh"
  defp shape_label(:thirteenth), do: "Thirteenth"
  defp shape_label(:add6), do: "Add 6"
  defp shape_label(:six_nine), do: "6/9"

  defp format_error({:invalid_mode_number, mode, size}),
    do: "Invalid mode #{mode}. Allowed range is 1..#{size}."

  defp format_error({:degree_out_of_range, degree, size}),
    do: "Degree #{degree} is outside scale size #{size}."

  defp format_error({:invalid_shape_for_strategy, shape, strategy}),
    do: "Shape #{inspect(shape)} is not supported by #{inspect(strategy)}."

  defp format_error(reason), do: inspect(reason)

  defp harmonic_identity_symbol(%ChordSpec.HarmonicIdentity{} = identity) do
    spec =
      ChordSpec.new!(%{
        harmonic_identity: identity,
        octave: 3,
        inversion: 0
      })

    ChordSpec.symbol_label(spec)
  end

  defp harmonic_identity_label(
         %{harmonic_identity: %ChordSpec.HarmonicIdentity{} = identity},
         generated_chord
       )
       when is_map(generated_chord) do
    symbol = harmonic_identity_symbol(identity)

    if harmonic_identity_exact_for_generated_chord?(identity, generated_chord) do
      symbol
    else
      note_list = Enum.join(Map.get(generated_chord, :note_names, []), "-")
      "#{symbol} (obs: #{note_list})"
    end
  end

  defp harmonic_identity_label(%{harmonic_identity: %ChordSpec.HarmonicIdentity{} = identity}, _),
    do: harmonic_identity_symbol(identity)

  defp harmonic_identity_label(_match, generated_chord) when is_map(generated_chord) do
    note_list = Enum.join(Map.get(generated_chord, :note_names, []), "-")
    root = Map.get(generated_chord, :root_note, "?")
    "#{root}[#{note_list}]"
  end

  defp harmonic_identity_label(_match, _generated_chord), do: "Unknown"

  defp harmonic_identity_exact_for_generated_chord?(
         %ChordSpec.HarmonicIdentity{root: root, quality: quality},
         generated_chord
       ) do
    with root_pc when is_integer(root_pc) <- ChordSpec.pitch_class_to_semitone(root),
         observed when is_list(observed) <- Map.get(generated_chord, :pitch_classes),
         expected <- quality_pitch_classes(root_pc, quality) do
      normalize_pitch_classes(observed) == expected
    else
      _ -> false
    end
  end

  defp quality_pitch_classes(root_pc, quality) when is_integer(root_pc) and is_atom(quality) do
    quality
    |> ChordSpec.quality_tones()
    |> Enum.map(&ChordSpec.tone_interval/1)
    |> Enum.map(&rem(root_pc + &1, 12))
    |> normalize_pitch_classes()
  rescue
    _ -> []
  end

  defp normalize_pitch_classes(values) when is_list(values) do
    values
    |> Enum.filter(&is_integer/1)
    |> Enum.map(&rem(&1 + 120, 12))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp format_quality(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_quality(value), do: to_string(value)

  defp resolve_harmonic_identities(
         generated_chord,
         scale_spec,
         keyboard_notes,
         strategy,
         shape,
         degree
       ) do
    bass_pitch_class =
      case keyboard_notes do
        [lowest | _] when is_integer(lowest) ->
          ChordSpec.note_name(lowest)
          |> elem(0)

        _ ->
          nil
      end

    HarmonicIdentityInference.infer(generated_chord.pitch_classes,
      scale_spec: scale_spec,
      bass_pitch_class: bass_pitch_class,
      preferred_root_pitch_class: generated_chord.root_pitch_class,
      preferred_strategy: strategy,
      preferred_shape: shape,
      preferred_degree: degree
    )
    |> Enum.map(&Map.put_new(&1, :source, :inferred))
  end

  defp identity_source_label(%{source: :direct}), do: "direct"
  defp identity_source_label(%{source: :inferred}), do: "inferred"
  defp identity_source_label(_match), do: "inferred"
end
