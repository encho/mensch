defmodule MenschWeb.AppLive do
  @moduledoc """
  Root LiveView for the Mensch app.

  Renders the active project's active pattern as a grid of tracks and
  16-step trigs, with transport controls (RECORD/PLAY/FUNC) plus a
  separate Trig Edit Mode:

    * Program Mode — RECORD gates whether tapping a trig modifies the
      pattern. When recording, FUNC selects whether a tap creates a Note
      Trig (FUNC off) or a Lock Trig (FUNC on).
    * Trig Edit Mode — edit parameter locks for one specific trig
      (long-press a trig to enter it).

  Every track has a Harmonic Context (Scale or Chromatic mode) and a
  SINGLE_NOTE Machine. Both provide Track-level defaults that a Trig may
  override via namespaced parameter locks (`harmonic_context` or
  `machine`); this distinction is preserved end-to-end, from the domain
  model through to the LiveView events below.

  State is held in-memory on the socket for now; there is no persistence
  or shared state across connections yet.
  """

  use MenschWeb, :live_view

  alias Mensch.App
  alias Mensch.Pattern
  alias Mensch.Project
  alias Mensch.Scale
  alias Mensch.Track
  alias Mensch.Trig
  alias Mensch.UIState

  @harmonic_keys %{"root" => :root, "scale" => :scale}

  @machine_keys %{
    "pitch" => :pitch,
    "octave" => :octave,
    "duration" => :duration,
    "velocity" => :velocity,
    "pressure" => :pressure,
    "aftertouch" => :aftertouch,
    "pitch_offset" => :pitch_offset,
    "release" => :release
  }

  @harmonic_order [:root, :scale]
  @machine_order [
    :pitch,
    :octave,
    :duration,
    :velocity,
    :pressure,
    :aftertouch,
    :pitch_offset,
    :release
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_app(App.new())
      |> assign(:ui, UIState.new())

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_record", _params, socket) do
    {:noreply, assign(socket, :ui, UIState.toggle_recording(socket.assigns.ui))}
  end

  @impl true
  def handle_event("toggle_play", _params, socket) do
    {:noreply, assign(socket, :ui, UIState.toggle_playing(socket.assigns.ui))}
  end

  @impl true
  def handle_event("stop", _params, socket) do
    {:noreply, assign(socket, :ui, UIState.stop_playing(socket.assigns.ui))}
  end

  @impl true
  def handle_event("toggle_func", _params, socket) do
    {:noreply, assign(socket, :ui, UIState.toggle_func(socket.assigns.ui))}
  end

  @impl true
  def handle_event("toggle_trig", %{"track_id" => track_id, "step" => step}, socket) do
    %{app: app, ui: ui} = socket.assigns

    socket =
      if ui.recording do
        app =
          App.apply_program_tap(
            app,
            String.to_integer(track_id),
            String.to_integer(step),
            UIState.trig_type(ui)
          )

        assign_app(socket, app)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_trig", %{"track_id" => track_id, "step" => step}, socket) do
    track_id = String.to_integer(track_id)
    step = String.to_integer(step)
    track = Pattern.track(socket.assigns.pattern, track_id)
    trig = track && Track.trig_at(track, step)

    socket =
      if trig && trig.type do
        assign(socket, :ui, UIState.enter_edit(socket.assigns.ui, track_id, step))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("exit_edit_trig", _params, socket) do
    {:noreply, assign(socket, :ui, UIState.exit_edit(socket.assigns.ui))}
  end

  @impl true
  def handle_event("lock_param", %{"namespace" => namespace, "key" => key}, socket) do
    %{app: app, ui: ui} = socket.assigns
    ns = parse_namespace(namespace)
    app = App.lock_param(app, ui.selected_track_id, ui.selected_step, ns, parse_key(ns, key))
    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event("clear_lock", %{"namespace" => namespace, "key" => key}, socket) do
    %{app: app, ui: ui} = socket.assigns
    ns = parse_namespace(namespace)
    app = App.clear_lock(app, ui.selected_track_id, ui.selected_step, ns, parse_key(ns, key))
    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event(
        "adjust_lock",
        %{"namespace" => namespace, "key" => key, "direction" => direction},
        socket
      ) do
    %{app: app, ui: ui} = socket.assigns
    ns = parse_namespace(namespace)

    app =
      App.adjust_lock(
        app,
        ui.selected_track_id,
        ui.selected_step,
        ns,
        parse_key(ns, key),
        parse_direction(direction)
      )

    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event("select_track", %{"track_id" => track_id}, socket) do
    app = App.set_active_track(socket.assigns.app, String.to_integer(track_id))
    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event("rename_project", %{"name" => name}, socket) do
    {:noreply, rename(socket, name, &App.rename_project(socket.assigns.app, &1))}
  end

  @impl true
  def handle_event("rename_pattern", %{"name" => name}, socket) do
    {:noreply, rename(socket, name, &App.rename_pattern(socket.assigns.app, &1))}
  end

  @impl true
  def handle_event("rename_track", %{"name" => name, "track_id" => track_id}, socket) do
    track_id = String.to_integer(track_id)
    {:noreply, rename(socket, name, &App.rename_track(socket.assigns.app, track_id, &1))}
  end

  @impl true
  def handle_event("toggle_harmonic_mode", _params, socket) do
    {:noreply, assign_app(socket, App.toggle_track_harmonic_mode(socket.assigns.app))}
  end

  @impl true
  def handle_event(
        "adjust_track_param",
        %{"namespace" => namespace, "key" => key, "direction" => direction},
        socket
      ) do
    ns = parse_namespace(namespace)

    app =
      App.adjust_track_default(
        socket.assigns.app,
        ns,
        parse_key(ns, key),
        parse_direction(direction)
      )

    {:noreply, assign_app(socket, app)}
  end

  defp assign_app(socket, app) do
    project = App.active_project(app)
    pattern = Project.active_pattern(project)

    assign(socket, app: app, project: project, pattern: pattern)
  end

  defp rename(socket, name, fun) do
    case String.trim(name) do
      "" -> socket
      trimmed -> assign_app(socket, fun.(trimmed))
    end
  end

  defp parse_direction("up"), do: :up
  defp parse_direction("down"), do: :down

  defp parse_namespace("harmonic_context"), do: :harmonic_context
  defp parse_namespace("machine"), do: :machine

  defp parse_key(:harmonic_context, key), do: Map.fetch!(@harmonic_keys, key)
  defp parse_key(:machine, key), do: Map.fetch!(@machine_keys, key)

  defp landmark?(step), do: step in [1, 5, 9, 13]

  defp pad_step(step), do: String.pad_leading(Integer.to_string(step), 2, "0")

  defp selected_trig?(
         %UIState{mode: :edit_trig, selected_track_id: track_id, selected_step: step},
         track_id,
         step
       ),
       do: true

  defp selected_trig?(_ui, _track_id, _step), do: false

  defp trig_classes(trig, selected?) do
    [
      "group relative flex aspect-square w-full select-none items-center justify-center rounded-[3px] border font-mono text-[11px] font-semibold tabular-nums transition-all duration-75 active:translate-y-px active:brightness-90",
      trig.type == :note &&
        "border-red-400 bg-red-600 text-red-50 shadow-[0_0_8px_-1px_rgba(248,113,113,0.5)]",
      trig.type == :lock &&
        "border-amber-300 bg-amber-500 text-neutral-950 shadow-[0_0_8px_-1px_rgba(252,211,77,0.5)]",
      is_nil(trig.type) &&
        "border-neutral-800 bg-neutral-800/80 text-neutral-600 hover:border-neutral-700",
      selected? && "ring-2 ring-neutral-50 ring-offset-2 ring-offset-neutral-900",
      landmark?(trig.step) && "p-1"
    ]
  end

  defp landmark_inner_classes(trig) do
    [
      "flex h-full w-full flex-col items-center justify-center gap-0.5 rounded-[2px] border-2",
      trig.type == :note && "border-red-400",
      trig.type == :lock && "border-amber-300",
      is_nil(trig.type) && "border-neutral-600"
    ]
  end

  defp trig_type_label(:note), do: "Note Trig"
  defp trig_type_label(:lock), do: "Lock Trig"
  defp trig_type_label(nil), do: "Empty"

  defp harmonic_label(:root), do: "Root"
  defp harmonic_label(:scale), do: "Scale"

  defp machine_label(:pitch, :scale), do: "Degree"
  defp machine_label(:pitch, :chromatic), do: "Note"
  defp machine_label(:octave, _mode), do: "Octave"
  defp machine_label(:duration, _mode), do: "Duration"
  defp machine_label(:velocity, _mode), do: "Velocity"
  defp machine_label(:pressure, _mode), do: "Pressure"
  defp machine_label(:aftertouch, _mode), do: "Aftertouch"
  defp machine_label(:pitch_offset, _mode), do: "Pitch Offset"
  defp machine_label(:release, _mode), do: "Release"

  defp format_scale(scale), do: scale |> Atom.to_string() |> String.capitalize()

  defp format_harmonic_value(:root, root), do: Scale.label(root)
  defp format_harmonic_value(:scale, scale), do: format_scale(scale)

  defp format_machine_value(:pitch, {:degree, degree}), do: Integer.to_string(degree)
  defp format_machine_value(:pitch, {:note, note_class}), do: Scale.label(note_class)
  defp format_machine_value(:octave, octave), do: Integer.to_string(octave)
  defp format_machine_value(:velocity, velocity), do: Integer.to_string(velocity)

  defp format_machine_value(key, value) when key in [:pressure, :aftertouch],
    do: "#{round(value * 100)}%"

  defp format_machine_value(:pitch_offset, value) do
    sign = if value >= 0, do: "+", else: ""
    "#{sign}#{round(value * 100)}%"
  end

  defp format_machine_value(key, {:beats, beats}) when key in [:duration, :release],
    do: "#{format_beats(beats)} beats"

  defp format_beats(n) when is_integer(n), do: Integer.to_string(n)

  defp format_beats(n) when is_float(n) do
    if n == Float.round(n),
      do: n |> trunc() |> Integer.to_string(),
      else: :erlang.float_to_binary(n, decimals: 2)
  end

  defp harmonic_rows(track, step) do
    effective = Track.effective_harmonic_context(track, step)
    trig = Track.trig_at(track, step)

    if effective.mode == :scale do
      Enum.map(@harmonic_order, fn key ->
        %{
          namespace: :harmonic_context,
          key: key,
          label: harmonic_label(key),
          value: format_harmonic_value(key, Map.fetch!(effective, key)),
          locked: Trig.locked?(trig, :harmonic_context, key)
        }
      end)
    else
      []
    end
  end

  defp machine_rows(track, step) do
    harmonic = Track.effective_harmonic_context(track, step)
    effective = Track.effective_machine(track, step)
    trig = Track.trig_at(track, step)

    Enum.map(@machine_order, fn key ->
      %{
        namespace: :machine,
        key: key,
        label: machine_label(key, harmonic.mode),
        value: format_machine_value(key, Map.fetch!(effective, key)),
        locked: Trig.locked?(trig, :machine, key)
      }
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      if assigns.ui.mode == :edit_trig do
        track = Pattern.track(assigns.pattern, assigns.ui.selected_track_id)
        trig = Track.trig_at(track, assigns.ui.selected_step)

        assign(assigns,
          edit_track: track,
          edit_trig: trig,
          edit_harmonic_rows: harmonic_rows(track, assigns.ui.selected_step),
          edit_machine_rows: machine_rows(track, assigns.ui.selected_step),
          edit_resolved_note:
            trig.type == :note && Track.resolved_note(track, assigns.ui.selected_step)
        )
      else
        assigns
      end

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-neutral-950 px-6 py-10 font-sans text-neutral-100">
        <header class="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <form phx-change="rename_project" phx-submit="rename_project">
              <input
                type="text"
                name="name"
                value={@project.name}
                autocomplete="off"
                phx-debounce="blur"
                class="w-full min-w-0 border-b border-transparent bg-transparent text-2xl font-semibold uppercase tracking-[0.3em] text-neutral-50 focus:border-neutral-700 focus:outline-none"
              />
            </form>
            <p class="mt-1 text-[10px] uppercase tracking-widest text-neutral-600">App</p>
          </div>

          <.transport_controls ui={@ui} />
        </header>

        <section class="rounded-md border border-neutral-800 bg-neutral-900/30 p-4">
          <div class="flex items-baseline justify-between">
            <.level_label kind="Project" name={@project.name} rename_event="rename_project" />
            <span class="text-[10px] uppercase tracking-widest text-neutral-500">
              {@project.bpm} BPM
            </span>
          </div>

          <section class="mt-4 rounded-md border border-neutral-800 bg-neutral-900/50 p-4">
            <.level_label
              kind={"Pattern ##{@pattern.id}"}
              name={@pattern.name}
              rename_event="rename_pattern"
            />

            <div class="mt-4 space-y-3">
              <div
                :for={track <- @pattern.tracks}
                id={"track-#{track.id}"}
                phx-click="select_track"
                phx-value-track_id={track.id}
                class={[
                  "cursor-pointer rounded-md border p-3 transition-colors duration-100",
                  track.id == @pattern.active_track_id &&
                    "border-amber-500/70 bg-neutral-900 ring-1 ring-amber-500/40",
                  track.id != @pattern.active_track_id &&
                    "border-neutral-800 bg-neutral-900 hover:border-neutral-700"
                ]}
              >
                <.level_label
                  kind={"Track ##{pad_step(track.id)}"}
                  name={track.name}
                  rename_event="rename_track"
                  track_id={track.id}
                />

                <div class="mt-4 grid grid-cols-2 gap-2.5 sm:grid-cols-4 sm:gap-2">
                  <div
                    :for={group <- Enum.chunk_every(track.trigs, 4)}
                    class="grid grid-cols-4 gap-2.5 sm:gap-2"
                  >
                    <div :for={trig <- group} class="relative">
                      <button
                        id={"trig-#{track.id}-#{trig.step}"}
                        type="button"
                        phx-hook=".TrigButton"
                        data-track-id={track.id}
                        data-step={trig.step}
                        class={trig_classes(trig, selected_trig?(@ui, track.id, trig.step))}
                      >
                        <div :if={landmark?(trig.step)} class={landmark_inner_classes(trig)}>
                          <span>{pad_step(trig.step)}</span>
                        </div>
                        <span :if={!landmark?(trig.step)}>{pad_step(trig.step)}</span>
                        <span
                          :if={trig.type == :note and map_size(trig.locks) > 0}
                          class="absolute right-0.5 top-0.5 h-1.5 w-1.5 rounded-full bg-amber-300 ring-1 ring-red-950"
                        />
                      </button>
                    </div>
                  </div>
                </div>

                <.track_defaults_panel :if={track.id == @pattern.active_track_id} track={track} />
              </div>
            </div>

            <.trig_edit_panel
              :if={@ui.mode == :edit_trig}
              track={@edit_track}
              trig={@edit_trig}
              harmonic_rows={@edit_harmonic_rows}
              machine_rows={@edit_machine_rows}
              resolved_note={@edit_resolved_note}
            />
          </section>
        </section>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".TrigButton">
        export default {
          mounted() {
            this.longPressMs = 450
            this.timer = null
            this.longPressed = false

            this.start = () => {
              this.longPressed = false
              this.timer = setTimeout(() => {
                this.longPressed = true
                this.pushEvent("edit_trig", { track_id: this.el.dataset.trackId, step: this.el.dataset.step })
              }, this.longPressMs)
            }

            this.finish = () => {
              clearTimeout(this.timer)
              if (!this.longPressed) {
                this.pushEvent("toggle_trig", { track_id: this.el.dataset.trackId, step: this.el.dataset.step })
              }
            }

            this.cancel = () => clearTimeout(this.timer)

            this.el.addEventListener("pointerdown", this.start)
            this.el.addEventListener("pointerup", this.finish)
            this.el.addEventListener("pointerleave", this.cancel)
            this.el.addEventListener("contextmenu", (e) => e.preventDefault())
          },
          destroyed() {
            clearTimeout(this.timer)
          }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :kind, :string, required: true
  attr :name, :string, required: true
  attr :rename_event, :string, required: true
  attr :track_id, :integer, default: nil

  defp level_label(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <span class="text-[10px] font-semibold uppercase tracking-widest text-neutral-500">
        {@kind}
      </span>
      <form phx-change={@rename_event} phx-submit={@rename_event} class="min-w-0">
        <input :if={@track_id} type="hidden" name="track_id" value={@track_id} />
        <input
          type="text"
          name="name"
          value={@name}
          autocomplete="off"
          phx-debounce="blur"
          class="w-40 max-w-full truncate border-b border-transparent bg-transparent text-xs font-medium text-neutral-200 focus:border-neutral-600 focus:outline-none"
        />
      </form>
    </div>
    """
  end

  attr :ui, UIState, required: true

  defp transport_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-5">
      <div class="flex items-center gap-1.5">
        <button
          type="button"
          phx-click="toggle_record"
          aria-label="Record"
          class="flex h-9 w-9 items-center justify-center rounded-sm border border-neutral-700 bg-neutral-900 transition-all duration-100 hover:bg-neutral-800 active:translate-y-px"
        >
          <span class={[
            "block h-3 w-3 rounded-full border-2",
            @ui.recording && "border-red-500",
            !@ui.recording && "border-neutral-600"
          ]} />
        </button>

        <button
          type="button"
          phx-click="toggle_play"
          aria-label="Play"
          class="flex h-9 w-9 items-center justify-center rounded-sm border border-neutral-700 bg-neutral-900 transition-all duration-100 hover:bg-neutral-800 active:translate-y-px"
        >
          <.icon
            name="hero-play"
            class={[
              "size-4",
              @ui.playing && "text-green-400",
              !@ui.playing && "text-neutral-600"
            ]}
          />
        </button>

        <button
          type="button"
          phx-click="stop"
          aria-label="Stop"
          class="group flex h-9 w-9 items-center justify-center rounded-sm border border-neutral-700 bg-neutral-900 transition-all duration-75 hover:bg-neutral-800 active:translate-y-px"
        >
          <.icon
            name="hero-stop"
            class={[
              "size-4 transition-colors duration-75 group-active:text-white",
              !@ui.playing && "text-white",
              @ui.playing && "text-neutral-600"
            ]}
          />
        </button>
      </div>

      <button
        type="button"
        phx-click="toggle_func"
        class={[
          "flex h-9 w-16 items-center justify-center gap-1.5 rounded-sm border text-[10px] font-semibold uppercase tracking-widest transition-all duration-100",
          @ui.func_active &&
            "border-amber-300 bg-amber-500 text-neutral-950 shadow-[inset_0_1px_3px_rgba(0,0,0,0.5)]",
          !@ui.func_active && "border-amber-950 bg-amber-900 text-amber-600 hover:bg-amber-800"
        ]}
      >
        <span class={[
          "h-1.5 w-1.5 rounded-full",
          @ui.func_active && "bg-amber-200 shadow-[0_0_6px_2px_rgba(252,211,77,0.9)]",
          !@ui.func_active && "bg-black/30"
        ]} /> Func
      </button>
    </div>
    """
  end

  attr :track, :map, required: true
  attr :trig, :map, required: true
  attr :harmonic_rows, :list, required: true
  attr :machine_rows, :list, required: true
  attr :resolved_note, :any, default: nil

  defp trig_edit_panel(assigns) do
    ~H"""
    <div class="mt-4 rounded-md border border-amber-500/40 bg-neutral-900 p-4">
      <div class="mb-4 flex items-center justify-between">
        <div>
          <p class="text-[10px] uppercase tracking-widest text-amber-500">
            Edit Trig {String.pad_leading(Integer.to_string(@trig.step), 2, "0")}
          </p>
          <p class="mt-0.5 text-xs text-neutral-400">
            {@track.name} · {trig_type_label(@trig.type)}
            <span :if={@resolved_note} class="text-amber-400">=&gt; {@resolved_note}</span>
          </p>
        </div>
        <button
          type="button"
          phx-click="exit_edit_trig"
          class="rounded-sm border border-neutral-700 px-2 py-1 text-[10px] uppercase tracking-widest text-neutral-400 hover:bg-neutral-800"
        >
          Back
        </button>
      </div>

      <div :if={@harmonic_rows != []} class="mb-4">
        <p class="mb-1 text-[10px] uppercase tracking-widest text-neutral-600">Harmonic</p>
        <.lock_rows_table rows={@harmonic_rows} />
      </div>

      <div>
        <p class="mb-1 text-[10px] uppercase tracking-widest text-neutral-600">
          Machine · Single Note
        </p>
        <.lock_rows_table rows={@machine_rows} />
      </div>
    </div>
    """
  end

  attr :rows, :list, required: true

  defp lock_rows_table(assigns) do
    ~H"""
    <table class="w-full text-left text-xs">
      <thead>
        <tr class="text-[10px] uppercase tracking-widest text-neutral-600">
          <th class="pb-2 font-normal">Parameter</th>
          <th class="pb-2 font-normal">Value</th>
          <th class="pb-2 font-normal">State</th>
          <th class="pb-2 text-right font-normal">Actions</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows} class="border-t border-neutral-800">
          <td class="py-2 text-neutral-300">{row.label}</td>
          <td class="py-2 text-neutral-100">{row.value}</td>
          <td class="py-2">
            <span class={[
              "rounded-sm px-1.5 py-0.5 text-[10px] uppercase tracking-widest",
              row.locked && "bg-amber-500/20 text-amber-400",
              !row.locked && "bg-neutral-800 text-neutral-500"
            ]}>
              <%= if row.locked do %>
                Locked
              <% else %>
                Inherited
              <% end %>
            </span>
          </td>
          <td class="py-2 text-right">
            <%= if row.locked do %>
              <div class="inline-flex items-center gap-1">
                <button
                  type="button"
                  phx-click="adjust_lock"
                  phx-value-namespace={row.namespace}
                  phx-value-key={row.key}
                  phx-value-direction="down"
                  class="h-6 w-6 rounded-sm border border-neutral-700 text-neutral-300 hover:bg-neutral-800"
                >
                  -
                </button>
                <button
                  type="button"
                  phx-click="adjust_lock"
                  phx-value-namespace={row.namespace}
                  phx-value-key={row.key}
                  phx-value-direction="up"
                  class="h-6 w-6 rounded-sm border border-neutral-700 text-neutral-300 hover:bg-neutral-800"
                >
                  +
                </button>
                <button
                  type="button"
                  phx-click="clear_lock"
                  phx-value-namespace={row.namespace}
                  phx-value-key={row.key}
                  class="rounded-sm border border-neutral-700 px-2 py-1 text-[10px] uppercase tracking-widest text-neutral-400 hover:bg-neutral-800"
                >
                  Clear
                </button>
              </div>
            <% else %>
              <button
                type="button"
                phx-click="lock_param"
                phx-value-namespace={row.namespace}
                phx-value-key={row.key}
                class="rounded-sm border border-amber-500/50 px-2 py-1 text-[10px] uppercase tracking-widest text-amber-400 hover:bg-amber-500/10"
              >
                Lock
              </button>
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :track, :map, required: true

  defp track_defaults_panel(assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2">
      <div class="rounded-sm border border-neutral-800 bg-neutral-950/40 p-3">
        <div class="mb-2 flex items-center justify-between">
          <span class="text-[10px] uppercase tracking-widest text-neutral-500">Harmonic</span>
          <button
            type="button"
            phx-click="toggle_harmonic_mode"
            class="rounded-sm border border-neutral-700 px-2 py-0.5 text-[10px] uppercase tracking-widest text-neutral-300 hover:bg-neutral-800"
          >
            {@track.harmonic_context.mode}
          </button>
        </div>

        <div :if={@track.harmonic_context.mode == :scale} class="space-y-1.5">
          <.default_row
            label="Root"
            value={Scale.label(@track.harmonic_context.root)}
            namespace="harmonic_context"
            param_key="root"
          />
          <.default_row
            label="Scale"
            value={format_scale(@track.harmonic_context.scale)}
            namespace="harmonic_context"
            param_key="scale"
          />
        </div>
      </div>

      <div class="rounded-sm border border-neutral-800 bg-neutral-950/40 p-3">
        <span class="text-[10px] uppercase tracking-widest text-neutral-500">Machine · Single Note</span>
        <div class="mt-2 space-y-1.5">
          <.default_row
            label={machine_label(:pitch, @track.harmonic_context.mode)}
            value={format_machine_value(:pitch, @track.machine.pitch)}
            namespace="machine"
            param_key="pitch"
          />
          <.default_row
            label="Octave"
            value={format_machine_value(:octave, @track.machine.octave)}
            namespace="machine"
            param_key="octave"
          />
          <.default_row
            label="Duration"
            value={format_machine_value(:duration, @track.machine.duration)}
            namespace="machine"
            param_key="duration"
          />
          <.default_row
            label="Velocity"
            value={format_machine_value(:velocity, @track.machine.velocity)}
            namespace="machine"
            param_key="velocity"
          />
          <.default_row
            label="Pressure"
            value={format_machine_value(:pressure, @track.machine.pressure)}
            namespace="machine"
            param_key="pressure"
          />
          <.default_row
            label="Aftertouch"
            value={format_machine_value(:aftertouch, @track.machine.aftertouch)}
            namespace="machine"
            param_key="aftertouch"
          />
          <.default_row
            label="Pitch Offset"
            value={format_machine_value(:pitch_offset, @track.machine.pitch_offset)}
            namespace="machine"
            param_key="pitch_offset"
          />
          <.default_row
            label="Release"
            value={format_machine_value(:release, @track.machine.release)}
            namespace="machine"
            param_key="release"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :namespace, :string, required: true
  attr :param_key, :string, required: true

  defp default_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between text-xs">
      <span class="text-neutral-500">{@label}</span>
      <div class="flex items-center gap-1.5">
        <span class="w-16 text-right font-mono tabular-nums text-neutral-200">{@value}</span>
        <button
          type="button"
          phx-click="adjust_track_param"
          phx-value-namespace={@namespace}
          phx-value-key={@param_key}
          phx-value-direction="down"
          class="h-5 w-5 rounded-sm border border-neutral-700 text-neutral-400 hover:bg-neutral-800"
        >
          -
        </button>
        <button
          type="button"
          phx-click="adjust_track_param"
          phx-value-namespace={@namespace}
          phx-value-key={@param_key}
          phx-value-direction="up"
          class="h-5 w-5 rounded-sm border border-neutral-700 text-neutral-400 hover:bg-neutral-800"
        >
          +
        </button>
      </div>
    </div>
    """
  end
end
