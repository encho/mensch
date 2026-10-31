defmodule MenschWeb.ChordProgressionsLive do
  use MenschWeb, :live_view

  alias Mensch.ChordProgressions

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:midi_status, Mensch.Midi.Connection.status())
     |> assign(:progressions, ChordProgressions.list_progressions())
     |> assign(:selected_ids, [])
     |> assign(:merge_modal_open, false)
     |> assign(:merge_name, "")
     |> assign(:merge_description, "")}
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_event("toggle_selection", %{"selected_id" => id} = params, socket) do
    selected = Map.get(params, "selected", "false") == "true"

    selected_ids =
      if selected do
        append_unique(socket.assigns.selected_ids, id)
      else
        Enum.reject(socket.assigns.selected_ids, &(&1 == id))
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("open_merge_modal", _params, socket) do
    selected_progressions = selected_progressions_in_order(socket)

    if length(selected_progressions) < 2 do
      {:noreply, put_flash(socket, :error, "Select at least two progressions to merge")}
    else
      default_name = default_merge_name(selected_progressions)

      {:noreply,
       socket
       |> assign(:merge_modal_open, true)
       |> assign(:merge_name, default_name)
       |> assign(:merge_description, "")}
    end
  end

  @impl true
  def handle_event("close_merge_modal", _params, socket) do
    {:noreply, assign(socket, :merge_modal_open, false)}
  end

  @impl true
  def handle_event("set_merge_form", %{"merge" => params}, socket) do
    {:noreply,
     socket
     |> assign(:merge_name, Map.get(params, "name", ""))
     |> assign(:merge_description, Map.get(params, "description", ""))}
  end

  @impl true
  def handle_event("move_merge_item", %{"id" => id, "direction" => direction}, socket) do
    selected_ids =
      case direction do
        "up" -> move_id(socket.assigns.selected_ids, id, -1)
        "down" -> move_id(socket.assigns.selected_ids, id, 1)
        _ -> socket.assigns.selected_ids
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("remove_merge_item", %{"id" => id}, socket) do
    selected_ids = Enum.reject(socket.assigns.selected_ids, &(&1 == id))

    if length(selected_ids) < 2 do
      {:noreply,
       socket
       |> assign(:selected_ids, selected_ids)
       |> assign(:merge_modal_open, false)
       |> put_flash(:error, "Select at least two progressions to merge")}
    else
      {:noreply, assign(socket, :selected_ids, selected_ids)}
    end
  end

  @impl true
  def handle_event("merge_selected_progressions", %{"merge" => params}, socket) do
    selected_ids = socket.assigns.selected_ids
    name = Map.get(params, "name", socket.assigns.merge_name)
    description = Map.get(params, "description", socket.assigns.merge_description)

    case ChordProgressions.merge_progressions(
           name,
           description,
           selected_ids
         ) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:progressions, ChordProgressions.list_progressions())
         |> assign(:selected_ids, [])
         |> assign(:merge_modal_open, false)
         |> put_flash(:info, "Merged progression created")
         |> push_navigate(to: ~p"/chord-progressions/#{record.id}")}

      {:error, :name_required} ->
        {:noreply, put_flash(socket, :error, "Name is required")}

      {:error, :no_sources_selected} ->
        {:noreply, put_flash(socket, :error, "Select at least one progression")}

      {:error, {:source_load_failed, id, :not_found}} ->
        {:noreply, put_flash(socket, :error, "Progression not found: #{id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Merge failed: #{inspect(reason)}")}
    end
  end

  def handle_event("merge_selected_progressions", _params, socket) do
    {:noreply, put_flash(socket, :error, "Invalid merge submission")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:progression}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title="Chord Progressions"
          subtitle="Saved chord progressions with playable detail pages."
        />

        <div class="flex flex-wrap items-center justify-end gap-2">
          <button
            type="button"
            phx-click="open_merge_modal"
            disabled={length(@selected_ids) < 2}
            class="rounded-sm border border-sky-300 bg-sky-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-sky-100 transition-colors duration-150 enabled:hover:bg-sky-400/30 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Merge into New Chord Progression
          </button>

          <.link
            navigate={~p"/chord-progressions/new"}
            class="rounded-sm border border-emerald-300 bg-emerald-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-emerald-100 transition-colors duration-150 hover:bg-emerald-400/30"
          >
            New Progression
          </.link>
        </div>

        <div class="ui-radius-table border border-zinc-700/60 bg-black/30 p-4">
          <%= if @progressions == [] do %>
            <p class="font-mono text-xs text-zinc-400">No saved chord progressions yet.</p>
          <% else %>
            <div class="space-y-2">
              <div
                :for={item <- @progressions}
                class="flex items-start gap-3 rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3 transition-colors duration-150 hover:border-zinc-500"
              >
                <form phx-change="toggle_selection" class="pt-1">
                  <input type="hidden" name="selected_id" value={item.id} />
                  <input type="hidden" name="selected" value="false" />
                  <input
                    type="checkbox"
                    name="selected"
                    value="true"
                    checked={item.id in @selected_ids}
                    class="h-4 w-4 cursor-pointer rounded border-zinc-500 bg-zinc-900 text-sky-400 focus:ring-sky-400"
                  />
                </form>

                <.link navigate={~p"/chord-progressions/#{item.id}"} class="min-w-0 flex-1">
                  <div class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
                    <div class="min-w-0">
                      <p class="truncate font-mono text-sm text-zinc-100">{item.name}</p>
                      <p class="mt-1 line-clamp-2 font-mono text-xs text-zinc-400">
                        {if String.trim(item.description) == "",
                          do: "No description",
                          else: item.description}
                      </p>
                    </div>
                    <div class="shrink-0 text-right font-mono text-[11px] text-zinc-500">
                      <p>{item.chord_count} chords</p>
                      <p>updated {item.updated_at}</p>
                    </div>
                  </div>
                </.link>
              </div>
            </div>
          <% end %>
        </div>

        <%= if @merge_modal_open do %>
          <div class="fixed inset-0 z-40 bg-black/70" phx-click="close_merge_modal"></div>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
            <div
              class="w-full max-w-2xl rounded-sm border border-zinc-700 bg-zinc-950 p-5 shadow-2xl"
              phx-click-away="close_merge_modal"
            >
              <div class="mb-4 flex items-start justify-between gap-4">
                <div>
                  <h2 class="font-mono text-sm text-zinc-100">Merge Chord Progressions</h2>
                  <p class="mt-1 font-mono text-xs text-zinc-400">
                    Reorder selected progressions to define chord order in the merged result.
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="close_merge_modal"
                  class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-xs text-zinc-300 hover:border-zinc-500"
                >
                  Close
                </button>
              </div>

              <.form
                for={%{}}
                as={:merge}
                phx-change="set_merge_form"
                phx-submit="merge_selected_progressions"
                id="merge-progressions-form"
                class="space-y-4"
              >
                <div class="grid gap-3 md:grid-cols-2">
                  <div class="space-y-1">
                    <label class="font-mono text-xs text-zinc-300" for="merge-name">Name</label>
                    <input
                      id="merge-name"
                      name="merge[name]"
                      value={@merge_name}
                      required
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900 px-3 py-2 font-mono text-xs text-zinc-100 focus:border-sky-400 focus:outline-none"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="font-mono text-xs text-zinc-300" for="merge-description">
                      Description
                    </label>
                    <input
                      id="merge-description"
                      name="merge[description]"
                      value={@merge_description}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900 px-3 py-2 font-mono text-xs text-zinc-100 focus:border-sky-400 focus:outline-none"
                    />
                  </div>
                </div>

                <div class="space-y-2 rounded-sm border border-zinc-700/70 bg-black/30 p-3">
                  <p class="font-mono text-xs text-zinc-400">Order of merged segments</p>

                  <div class="space-y-2">
                    <%= for {id, index} <- Enum.with_index(@selected_ids) do %>
                      <% item = progression_by_id(@progressions, id) %>
                      <%= if item do %>
                        <div class="flex items-center gap-2 rounded-sm border border-zinc-700 bg-zinc-950/70 p-2">
                          <span class="w-6 text-center font-mono text-xs text-zinc-400">{index + 1}</span>
                          <div class="min-w-0 flex-1">
                            <p class="truncate font-mono text-xs text-zinc-100">{item.name}</p>
                            <p class="font-mono text-[11px] text-zinc-500">
                              {item.chord_count} chords
                            </p>
                          </div>
                          <div class="flex items-center gap-1">
                            <button
                              type="button"
                              phx-click="move_merge_item"
                              phx-value-id={id}
                              phx-value-direction="up"
                              disabled={index == 0}
                              class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-[11px] text-zinc-200 enabled:hover:border-zinc-500 disabled:opacity-40"
                            >
                              Up
                            </button>
                            <button
                              type="button"
                              phx-click="move_merge_item"
                              phx-value-id={id}
                              phx-value-direction="down"
                              disabled={index == length(@selected_ids) - 1}
                              class="rounded-sm border border-zinc-600 px-2 py-1 font-mono text-[11px] text-zinc-200 enabled:hover:border-zinc-500 disabled:opacity-40"
                            >
                              Down
                            </button>
                            <button
                              type="button"
                              phx-click="remove_merge_item"
                              phx-value-id={id}
                              class="rounded-sm border border-rose-800/80 px-2 py-1 font-mono text-[11px] text-rose-200 hover:border-rose-700"
                            >
                              Remove
                            </button>
                          </div>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center justify-end gap-2">
                  <button
                    type="button"
                    phx-click="close_merge_modal"
                    class="rounded-sm border border-zinc-600 px-3 py-1.5 font-mono text-xs text-zinc-200 hover:border-zinc-500"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={length(@selected_ids) < 2}
                    class="rounded-sm border border-sky-300 bg-sky-400/20 px-3 py-1.5 font-mono text-xs font-semibold text-sky-100 transition-colors duration-150 enabled:hover:bg-sky-400/30 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Create Merged Progression
                  </button>
                </div>
              </.form>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp append_unique(ids, id) do
    if id in ids, do: ids, else: ids ++ [id]
  end

  defp progression_by_id(progressions, id) do
    Enum.find(progressions, &(&1.id == id))
  end

  defp selected_progressions_in_order(socket) do
    socket.assigns.selected_ids
    |> Enum.map(&progression_by_id(socket.assigns.progressions, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp default_merge_name(selected_progressions) do
    names = Enum.map(selected_progressions, & &1.name)

    case names do
      [] -> "Merged Chord Progression"
      [name] -> "Merged #{name}"
      [first, second] -> "Merged #{first} + #{second}"
      [first | rest] -> "Merged #{first} + #{length(rest)} more"
    end
  end

  defp move_id(ids, id, delta) do
    with current_index when is_integer(current_index) <- Enum.find_index(ids, &(&1 == id)),
         target_index <- current_index + delta,
         true <- target_index >= 0 and target_index < length(ids) do
      value = Enum.at(ids, current_index)

      ids
      |> List.delete_at(current_index)
      |> List.insert_at(target_index, value)
    else
      _ -> ids
    end
  end
end
