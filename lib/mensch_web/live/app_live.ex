defmodule MenschWeb.AppLive do
  @moduledoc """
  Root LiveView for the Mensch app.

  Renders the active project's active pattern as a grid of tracks and
  16-step trigs. State is held in-memory on the socket for now; there is
  no persistence or shared state across connections yet.
  """

  use MenschWeb, :live_view

  alias Mensch.App
  alias Mensch.Project

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_app(socket, App.new())}
  end

  @impl true
  def handle_event("toggle_trig", %{"track_id" => track_id, "step" => step}, socket) do
    app = App.toggle_trig(socket.assigns.app, String.to_integer(track_id), String.to_integer(step))
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

  @impl true
  def render(assigns) do
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
                    phx-click="toggle_trig"
                    phx-value-track_id={track.id}
                    phx-value-step={trig.step}
                    class={[
                      "flex aspect-square flex-1 items-center justify-center rounded-sm border text-[10px] font-medium transition-colors duration-100",
                      rem(trig.step - 1, 4) == 0 && trig.step > 1 && "ml-2",
                      trig.enabled && "border-amber-400 bg-amber-500 text-neutral-950",
                      !trig.enabled &&
                        "border-neutral-700 bg-neutral-800 text-neutral-500 hover:bg-neutral-700"
                    ]}
                  >
                    {trig.step}
                  </button>
                </div>
              </div>
            </div>
          </section>
        </section>
      </div>
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
end
