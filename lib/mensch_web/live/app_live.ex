defmodule MenschWeb.AppLive do
  @moduledoc """
  Root LiveView for the Mensch app.

  Renders the active project's active pattern as a grid of tracks and
  16-step trigs, with two interaction modes:

    * Program Mode — choose a trig type (Note or Lock) and tap steps to
      create/remove trigs of that type.
    * Trig Edit Mode — edit parameter locks for one specific trig
      (long-press a trig in Program Mode to enter it).

  State is held in-memory on the socket for now; there is no persistence
  or shared state across connections yet.
  """

  use MenschWeb, :live_view

  alias Mensch.App
  alias Mensch.Pattern
  alias Mensch.Project
  alias Mensch.Track
  alias Mensch.UIState

  @param_keys %{
    "expression" => :expression,
    "pressure" => :pressure,
    "duration" => :duration,
    "release" => :release
  }

  @param_order [:expression, :pressure, :duration, :release]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_app(App.new())
      |> assign(:ui, UIState.new())

    {:ok, socket}
  end

  @impl true
  def handle_event("set_trig_type", %{"type" => type}, socket) do
    ui = UIState.set_trig_type(socket.assigns.ui, parse_trig_type(type))
    {:noreply, assign(socket, :ui, ui)}
  end

  @impl true
  def handle_event("toggle_trig", %{"track_id" => track_id, "step" => step}, socket) do
    %{app: app, ui: ui} = socket.assigns

    app =
      App.apply_program_tap(app, String.to_integer(track_id), String.to_integer(step), ui.trig_type)

    {:noreply, assign_app(socket, app)}
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
  def handle_event("lock_param", %{"key" => key}, socket) do
    %{app: app, ui: ui} = socket.assigns
    app = App.lock_param(app, ui.selected_track_id, ui.selected_step, parse_key(key))
    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event("clear_lock", %{"key" => key}, socket) do
    %{app: app, ui: ui} = socket.assigns
    app = App.clear_lock(app, ui.selected_track_id, ui.selected_step, parse_key(key))
    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event("adjust_lock", %{"key" => key, "direction" => direction}, socket) do
    %{app: app, ui: ui} = socket.assigns

    app =
      App.adjust_lock(app, ui.selected_track_id, ui.selected_step, parse_key(key), parse_direction(direction))

    {:noreply, assign_app(socket, app)}
  end

  @impl true
  def handle_event("select_track", %{"track_id" => track_id}, socket) do
    app = App.set_active_track(socket.assigns.app, String.to_integer(track_id))
    {:noreply, assign_app(socket, app)}
  end

  defp assign_app(socket, app) do
    project = App.active_project(app)
    pattern = Project.active_pattern(project)

    assign(socket, app: app, project: project, pattern: pattern)
  end

  defp parse_trig_type("note"), do: :note
  defp parse_trig_type("lock"), do: :lock

  defp parse_direction("up"), do: :up
  defp parse_direction("down"), do: :down

  defp parse_key(key), do: Map.fetch!(@param_keys, key)

  defp trig_glyph(:note), do: "●"
  defp trig_glyph(:lock), do: "◇"
  defp trig_glyph(nil), do: "·"

  defp trig_type_label(:note), do: "Note Trig"
  defp trig_type_label(:lock), do: "Lock Trig"
  defp trig_type_label(nil), do: "Empty"

  defp label_for(:expression), do: "Expression"
  defp label_for(:pressure), do: "Pressure"
  defp label_for(:duration), do: "Duration"
  defp label_for(:release), do: "Release"

  defp format_value(key, value) when key in [:expression, :pressure] do
    "#{round(value * 100)}%"
  end

  defp format_value(key, {:beats, beats}) when key in [:duration, :release] do
    "#{format_beats(beats)} beats"
  end

  defp format_beats(n) when is_integer(n), do: Integer.to_string(n)

  defp format_beats(n) when is_float(n) do
    if n == Float.round(n), do: n |> trunc() |> Integer.to_string(), else: :erlang.float_to_binary(n, decimals: 2)
  end

  defp param_rows(track, step) do
    effective = Track.effective_params(track, step)
    trig = Track.trig_at(track, step)

    Enum.map(@param_order, fn key ->
      %{
        key: key,
        label: label_for(key),
        value: format_value(key, Map.fetch!(effective, key)),
        locked: Map.has_key?(trig.locks, key)
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
          edit_rows: param_rows(track, assigns.ui.selected_step)
        )
      else
        assigns
      end

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-neutral-950 px-6 py-10 font-sans text-neutral-100">
        <header class="mb-8">
          <h1 class="text-2xl font-semibold tracking-[0.3em] text-neutral-50">MENSCH</h1>
          <p class="mt-1 text-[10px] uppercase tracking-widest text-neutral-600">App</p>
        </header>

        <section class="rounded-md border border-neutral-800 bg-neutral-900/30 p-4">
          <div class="flex items-baseline justify-between">
            <.level_label kind="Project" name={@project.name} />
            <span class="text-[10px] uppercase tracking-widest text-neutral-500">
              {@project.bpm} BPM
            </span>
          </div>

          <section class="mt-4 rounded-md border border-neutral-800 bg-neutral-900/50 p-4">
            <.level_label kind="Pattern" name={@pattern.name} />

            <%= if @ui.mode == :edit_trig do %>
              <.trig_edit_panel track={@edit_track} trig={@edit_trig} rows={@edit_rows} />
            <% else %>
              <.program_controls trig_type={@ui.trig_type} />

              <div class="mt-4 space-y-3 border-l border-neutral-800 pl-4">
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
                  <.level_label kind="Track" name={track.name} active={track.id == @pattern.active_track_id} />

                  <div class="mt-3 flex w-full items-start gap-1 border-l border-neutral-800 pl-4">
                    <button
                      :for={trig <- track.trigs}
                      id={"trig-#{track.id}-#{trig.step}"}
                      type="button"
                      phx-hook=".TrigButton"
                      data-track-id={track.id}
                      data-step={trig.step}
                      class={[
                        "flex aspect-square flex-1 select-none items-center justify-center rounded-sm border text-sm font-medium transition-colors duration-100",
                        rem(trig.step - 1, 4) == 0 && trig.step > 1 && "ml-2",
                        trig.type == :note && "border-amber-400 bg-amber-500 text-neutral-950",
                        trig.type == :lock && "border-sky-400 bg-neutral-900 text-sky-400",
                        is_nil(trig.type) &&
                          "border-neutral-700 bg-neutral-800 text-neutral-600 hover:bg-neutral-700"
                      ]}
                    >
                      {trig_glyph(trig.type)}
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
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
  attr :active, :boolean, default: false

  defp level_label(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <span class="text-[10px] font-semibold uppercase tracking-widest text-neutral-500">
        {@kind}
      </span>
      <span class={[
        "text-xs font-medium",
        @active && "text-amber-400",
        !@active && "text-neutral-200"
      ]}>
        {@name}
      </span>
      <span :if={@active} class="text-[9px] uppercase tracking-widest text-amber-500">
        active
      </span>
    </div>
    """
  end

  attr :trig_type, :atom, required: true

  defp program_controls(assigns) do
    ~H"""
    <div class="mb-3 mt-4 flex items-center gap-2">
      <span class="text-[10px] uppercase tracking-widest text-neutral-500">Trig Type</span>
      <div class="flex overflow-hidden rounded-sm border border-neutral-700">
        <button
          type="button"
          phx-click="set_trig_type"
          phx-value-type="note"
          class={[
            "px-3 py-1 text-[11px] font-semibold uppercase tracking-widest transition-colors duration-100",
            @trig_type == :note && "bg-amber-500 text-neutral-950",
            @trig_type != :note && "bg-neutral-900 text-neutral-500 hover:bg-neutral-800"
          ]}
        >
          Note
        </button>
        <button
          type="button"
          phx-click="set_trig_type"
          phx-value-type="lock"
          class={[
            "border-l border-neutral-700 px-3 py-1 text-[11px] font-semibold uppercase tracking-widest transition-colors duration-100",
            @trig_type == :lock && "bg-sky-500 text-neutral-950",
            @trig_type != :lock && "bg-neutral-900 text-neutral-500 hover:bg-neutral-800"
          ]}
        >
          Lock
        </button>
      </div>
    </div>
    """
  end

  attr :track, :map, required: true
  attr :trig, :map, required: true
  attr :rows, :list, required: true

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
                    phx-value-key={row.key}
                    phx-value-direction="down"
                    class="h-6 w-6 rounded-sm border border-neutral-700 text-neutral-300 hover:bg-neutral-800"
                  >
                    -
                  </button>
                  <button
                    type="button"
                    phx-click="adjust_lock"
                    phx-value-key={row.key}
                    phx-value-direction="up"
                    class="h-6 w-6 rounded-sm border border-neutral-700 text-neutral-300 hover:bg-neutral-800"
                  >
                    +
                  </button>
                  <button
                    type="button"
                    phx-click="clear_lock"
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
    </div>
    """
  end
end
