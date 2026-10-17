defmodule MenschWeb.SamplesLive do
  use MenschWeb, :live_view

  alias Mensch.Machine
  alias Mensch.SampleContext
  alias Mensch.SampleDb
  alias Mensch.SampleDefinition

  @default_sort "created_at"
  @default_dir "desc"
  @sortable_columns ["name", "bpm", "time_signature", "duration", "created_at", "machines"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:samples, SampleDb.default_samples())
     |> assign(:sort, @default_sort)
     |> assign(:dir, @default_dir)
     |> assign(:table_rows, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort = normalize_sort(Map.get(params, "sort"))
    dir = normalize_dir(Map.get(params, "dir"))

    rows =
      socket.assigns.samples
      |> build_rows()
      |> sort_rows(sort, dir)

    {:noreply, assign(socket, sort: sort, dir: dir, table_rows: rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} midi_status={Mensch.Midi.Connection.status()} nav_active={:samples}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <div class="space-y-1">
          <h1 class="font-mono text-2xl text-zinc-100">Samples</h1>
          <p class="font-mono text-xs text-zinc-400">Sample library with sortable metadata.</p>
        </div>

        <div class="ui-radius-table overflow-x-auto border border-zinc-700/60">
          <table class="w-full min-w-[980px] text-left font-mono text-[11px] text-zinc-200">
            <thead>
              <tr class="border-b border-zinc-700/70 text-zinc-400">
                <th class="px-3 py-2 font-normal">
                  <.sort_header label="Sample name" column="name" sort={@sort} dir={@dir} />
                </th>
                <th class="px-3 py-2 font-normal">
                  <.sort_header label="BPM" column="bpm" sort={@sort} dir={@dir} />
                </th>
                <th class="px-3 py-2 font-normal">
                  <.sort_header
                    label="Time signature"
                    column="time_signature"
                    sort={@sort}
                    dir={@dir}
                  />
                </th>
                <th class="px-3 py-2 font-normal">
                  <.sort_header label="Duration" column="duration" sort={@sort} dir={@dir} />
                </th>
                <th class="px-3 py-2 font-normal">
                  <.sort_header label="Created at" column="created_at" sort={@sort} dir={@dir} />
                </th>
                <th class="px-3 py-2 font-normal">
                  <.sort_header label="Machines" column="machines" sort={@sort} dir={@dir} />
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @table_rows} class="border-b border-zinc-700/40 last:border-b-0">
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/samples/#{row.id}"}
                    class="text-zinc-100 transition-colors duration-150 hover:text-cyan-200"
                  >
                    {row.name}
                  </.link>
                </td>
                <td class="px-3 py-2">{row.bpm}</td>
                <td class="px-3 py-2">{row.time_signature_label}</td>
                <td class="px-3 py-2">{row.duration_label}</td>
                <td class="px-3 py-2">{row.created_at_label}</td>
                <td class="px-3 py-2">{row.machines_label}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :column, :string, required: true
  attr :sort, :string, required: true
  attr :dir, :string, required: true

  defp sort_header(assigns) do
    next_dir =
      if assigns.sort == assigns.column and assigns.dir == "asc", do: "desc", else: "asc"

    active? = assigns.sort == assigns.column

    icon_name =
      cond do
        not active? -> "hero-arrows-up-down"
        assigns.dir == "asc" -> "hero-chevron-up"
        true -> "hero-chevron-down"
      end

    assigns = assign(assigns, next_dir: next_dir, active?: active?, icon_name: icon_name)

    ~H"""
    <.link
      patch={~p"/samples?sort=#{@column}&dir=#{@next_dir}"}
      class={[
        "inline-flex items-center gap-1 transition-colors duration-150",
        @active? && "text-zinc-100",
        not @active? && "text-zinc-400 hover:text-zinc-200"
      ]}
    >
      <span>{@label}</span>
      <.icon name={@icon_name} class="size-3" />
    </.link>
    """
  end

  defp build_rows(samples) when is_list(samples) do
    Enum.map(samples, fn %SampleDefinition{} = sample ->
      sample_context = sample.sample_context
      total_mbeats = SampleDb.sample_total_length_mbeats(sample)

      machines =
        sample.sample_entries
        |> Enum.map(fn entry -> entry.machine |> Machine.id() |> Atom.to_string() end)
        |> Enum.uniq()
        |> Enum.sort()

      {time_num, time_den} = sample_context.time_signature

      %{
        id: sample.id,
        name: sample.name,
        bpm: sample_context.bpm,
        time_signature_sort: {time_num, time_den},
        time_signature_label: "#{time_num}/#{time_den}",
        duration_mbeats: total_mbeats,
        duration_label: sample_duration_label(total_mbeats, sample_context),
        created_at: sample.created_at,
        created_at_label: created_at_label(sample.created_at),
        machines: machines,
        machines_label: Enum.join(machines, ", ")
      }
    end)
  end

  defp sort_rows(rows, sort, dir) do
    sorter =
      case sort do
        "name" -> &{String.downcase(&1.name), &1.id}
        "bpm" -> &{&1.bpm, String.downcase(&1.name)}
        "time_signature" -> &{&1.time_signature_sort, String.downcase(&1.name)}
        "duration" -> &{&1.duration_mbeats, String.downcase(&1.name)}
        "created_at" -> &{&1.created_at || ~U[1970-01-01 00:00:00Z], String.downcase(&1.name)}
        "machines" -> &{&1.machines_label, String.downcase(&1.name)}
        _ -> &{&1.created_at || ~U[1970-01-01 00:00:00Z], String.downcase(&1.name)}
      end

    Enum.sort_by(rows, sorter, sort_direction(dir))
  end

  defp sort_direction("asc"), do: :asc
  defp sort_direction(_), do: :desc

  defp normalize_sort(sort) when sort in @sortable_columns, do: sort
  defp normalize_sort(_), do: @default_sort

  defp normalize_dir("asc"), do: "asc"
  defp normalize_dir("desc"), do: "desc"
  defp normalize_dir(_), do: @default_dir

  defp sample_duration_label(total_mbeats, %SampleContext{} = sample_context) do
    duration_ms = SampleContext.mbeats_to_ms(sample_context, total_mbeats)
    minutes = div(duration_ms, 60_000)
    seconds = div(rem(duration_ms, 60_000), 1000)
    millis = rem(duration_ms, 1000)
    "#{minutes}m #{seconds}s #{millis}ms"
  end

  defp created_at_label(%DateTime{} = created_at) do
    created_at
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  end

  defp created_at_label(_), do: "-"
end
