defmodule MenschWeb.ChordMatrixShowLive do
  use MenschWeb, :live_view

  alias Mensch.ChordMatrices
  alias Mensch.ChordMatrixPadPlayer
  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordMatrix
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver
  alias Mensch.SampleContext
  alias Mensch.SampleBlueprint
  alias Mensch.PerformanceAssembler
  alias MenschWeb.FullPianoKeyboard

  @mpe_chart_colors ["#FF7A1A", "#2FD5C8", "#75B8FF", "#B188FF", "#9BF25A", "#FF5D8F"]
  @mpe_chart_height 84

  @impl true
  def mount(_params, _session, socket) do
    machine_settings = default_machine_settings()

    {:ok,
     socket
     |> assign(:midi_status, Mensch.Midi.Connection.status())
     |> assign(:record, nil)
     |> assign(:selected_pad, nil)
     |> assign(:selected_row, nil)
     |> assign(:selected_column, nil)
     |> assign(:chord_matrix_play_mode, true)
     |> assign(:show_detail_mpe_data, false)
     |> assign(:keyboard_active_notes, [])
     |> assign(:keyboard_source, "No chord selected")
     |> assign(:latest_pad_performance, nil)
     |> assign(:note_matrix, [])
     |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})
     |> assign(:pressure_chart, [])
     |> assign(:slide_chart, [])
     |> assign(:bend_chart, [])
     |> assign(:pressure_axis, pressure_slide_axis())
     |> assign(:slide_axis, pressure_slide_axis())
     |> assign(:bend_axis, bend_axis({-1.0, 1.0}))
     |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
     |> assign(:progressions, ChordProgressions.list_progressions())
     |> assign(:expanded_progression_ids, MapSet.new())
     |> assign(:progression_records, %{})
     |> assign(:bpm_form, to_form(%{"bpm" => "120"}, as: :chord_matrix))
     |> assign(:frame_mbeats_form, frame_mbeats_form(50))
     |> assign(:duration_form, duration_form(4000))
     |> assign(:time_signature_form, time_signature_form({4, 4}))
     |> assign(:machine_settings, machine_settings)
     |> assign(:machine_schema, machine_settings_schema(machine_settings))
     |> assign(:bulk_assign_confirm, nil)
     |> assign(:preview_note_channels, [])
     |> assign(:preview_stop_ref, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case ChordMatrices.fetch_chord_matrix(id) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:record, record)
         |> assign(:bpm_form, bpm_form(record.chord_matrix.bpm))
         |> assign(:frame_mbeats_form, frame_mbeats_form(record.chord_matrix.frame_mbeats))
         |> assign(:duration_form, duration_form(record.chord_matrix.duration_mbeats))
         |> assign(:time_signature_form, time_signature_form(record.chord_matrix.time_signature))
         |> assign_machine_settings(record.chord_matrix.machine)
         |> assign_keyboard_from_selected_pad()}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Chord matrix not found")
         |> push_navigate(to: ~p"/chord-matrix")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to load chord matrix: #{inspect(reason)}")
         |> push_navigate(to: ~p"/chord-matrix")}
    end
  end

  @impl true
  def handle_event("reconnect_midi", _params, socket) do
    {:noreply, assign(socket, :midi_status, Mensch.Midi.Connection.reconnect())}
  end

  @impl true
  def handle_event("select_pad", %{"row" => row, "column" => column}, socket) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         {:ok, normalized_column} <- parse_non_negative_integer(column),
         :ok <-
           ensure_selected_pad_in_bounds(socket.assigns.record, normalized_row, normalized_column) do
      socket =
        socket
        |> assign(:selected_pad, {normalized_row, normalized_column})
        |> assign(:selected_row, nil)
        |> assign(:selected_column, nil)
        |> assign_keyboard_from_selected_pad()

      if socket.assigns.chord_matrix_play_mode do
        socket = stop_preview(socket)

        case ChordMatrixPadPlayer.performance_for_pad(
               socket.assigns.record,
               normalized_row,
               normalized_column
             ) do
          {:ok, performance} ->
            socket = maybe_assign_detail_mpe_data(socket, performance)

            case ChordMatrixPadPlayer.play_performance(performance) do
              :ok ->
                {:noreply, socket}

              {:error, :disconnected} ->
                {:noreply, put_flash(socket, :error, "MIDI is disconnected")}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Pad playback failed: #{inspect(reason)}")}
            end

          {:error, :pad_unassigned} ->
            {:noreply, clear_detail_mpe_data(socket)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Pad playback failed: #{inspect(reason)}")}
        end
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid pad selection")}
    end
  end

  @impl true
  def handle_event("toggle_matrix_play_mode", _params, socket) do
    {:noreply, assign(socket, :chord_matrix_play_mode, !socket.assigns.chord_matrix_play_mode)}
  end

  @impl true
  def handle_event("toggle_display_detail_mpe_data", _params, socket) do
    show_detail_mpe_data = !socket.assigns.show_detail_mpe_data

    socket =
      socket
      |> assign(:show_detail_mpe_data, show_detail_mpe_data)
      |> maybe_refresh_detail_mpe_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_bpm", %{"chord_matrix" => %{"bpm" => bpm_value}}, socket) do
    with {:ok, parsed_bpm} <- parse_positive_integer(bpm_value),
         {:ok, record} <- ChordMatrices.update_bpm(socket.assigns.record.id, parsed_bpm) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:bpm_form, bpm_form(record.chord_matrix.bpm))
       |> put_flash(:info, "BPM updated")}
    else
      {:error, :invalid_integer} ->
        {:noreply,
         socket
         |> assign(:bpm_form, bpm_form(bpm_value))
         |> put_flash(:error, "BPM must be a positive integer")}

      {:error, :invalid_bpm} ->
        {:noreply,
         socket
         |> assign(:bpm_form, bpm_form(bpm_value))
         |> put_flash(:error, "BPM must be a positive integer")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update BPM: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("update_frame_mbeats", %{"chord_matrix" => %{"frame_mbeats" => value}}, socket) do
    with {:ok, parsed_frame_mbeats} <- parse_positive_integer(value),
         {:ok, record} <-
           ChordMatrices.update_frame_mbeats(socket.assigns.record.id, parsed_frame_mbeats) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:frame_mbeats_form, frame_mbeats_form(record.chord_matrix.frame_mbeats))
       |> put_flash(:info, "Frame mbeats updated")}
    else
      {:error, :invalid_integer} ->
        {:noreply,
         socket
         |> assign(:frame_mbeats_form, frame_mbeats_form(value))
         |> put_flash(:error, "Frame mbeats must be a positive divisor of 1000")}

      {:error, :invalid_frame_mbeats} ->
        {:noreply,
         socket
         |> assign(:frame_mbeats_form, frame_mbeats_form(value))
         |> put_flash(:error, "Frame mbeats must be a positive divisor of 1000")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update frame mbeats: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event(
        "update_duration_mbeats",
        %{"chord_matrix" => %{"duration_mbeats" => value}},
        socket
      ) do
    with {:ok, parsed_duration_mbeats} <- parse_positive_integer(value),
         {:ok, record} <-
           ChordMatrices.update_duration_mbeats(socket.assigns.record.id, parsed_duration_mbeats) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:duration_form, duration_form(record.chord_matrix.duration_mbeats))
       |> put_flash(:info, "Duration updated")}
    else
      {:error, :invalid_integer} ->
        {:noreply,
         socket
         |> assign(:duration_form, duration_form(value))
         |> put_flash(:error, "Duration must be a positive integer")}

      {:error, :invalid_duration_mbeats} ->
        {:noreply,
         socket
         |> assign(:duration_form, duration_form(value))
         |> put_flash(:error, "Duration must be a positive integer")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update duration: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event(
        "update_time_signature",
        %{
          "chord_matrix" => %{
            "time_signature_numerator" => num,
            "time_signature_denominator" => den
          }
        },
        socket
      ) do
    with {:ok, parsed_num} <- parse_positive_integer(num),
         {:ok, parsed_den} <- parse_positive_integer(den),
         {:ok, record} <-
           ChordMatrices.update_time_signature(socket.assigns.record.id, {parsed_num, parsed_den}) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:time_signature_form, time_signature_form(record.chord_matrix.time_signature))
       |> put_flash(:info, "Time signature updated")}
    else
      {:error, :invalid_integer} ->
        {:noreply,
         socket
         |> assign(
           :time_signature_form,
           time_signature_form(%{"numerator" => num, "denominator" => den})
         )
         |> put_flash(:error, "Time signature must be positive integers")}

      {:error, :invalid_time_signature} ->
        {:noreply,
         socket
         |> assign(
           :time_signature_form,
           time_signature_form(%{"numerator" => num, "denominator" => den})
         )
         |> put_flash(:error, "Time signature must be positive integers")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to update time signature: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("set_machine_settings", %{"machine" => machine_params}, socket) do
    current_settings = socket.assigns.machine_settings

    selected_blueprint_id =
      Map.get(machine_params, "blueprint_id", Map.get(current_settings, "blueprint_id"))

    incoming_additional = Map.get(machine_params, "additional", %{})

    normalized_settings =
      if selected_blueprint_id != Map.get(current_settings, "blueprint_id") do
        normalize_machine_settings(selected_blueprint_id, %{})
      else
        normalize_machine_settings(selected_blueprint_id, incoming_additional)
      end

    {:noreply,
     socket
     |> assign(:machine_settings, normalized_settings)
     |> assign(:machine_schema, machine_settings_schema(normalized_settings))}
  end

  @impl true
  def handle_event("save_machine_settings", %{"machine" => machine_params}, socket) do
    blueprint_id =
      Map.get(machine_params, "blueprint_id", socket.assigns.machine_settings["blueprint_id"])

    additional = Map.get(machine_params, "additional", %{})

    case ChordMatrices.update_machine(socket.assigns.record.id, blueprint_id, additional) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:record, record)
         |> assign_machine_settings(record.chord_matrix.machine)
         |> put_flash(:info, "Machine settings updated")}

      {:error, reason} ->
        normalized_settings = normalize_machine_settings(blueprint_id, additional)

        {:noreply,
         socket
         |> assign(:machine_settings, normalized_settings)
         |> assign(:machine_schema, machine_settings_schema(normalized_settings))
         |> put_flash(:error, "Failed to update machine settings: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("select_row", %{"row" => row}, socket) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         :ok <- ensure_row_in_bounds(socket.assigns.record, normalized_row) do
      {:noreply,
       socket
       |> assign(:selected_row, normalized_row)
       |> assign(:selected_column, nil)
       |> assign(:selected_pad, nil)
       |> assign_keyboard_from_selected_pad()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid row selection")}
    end
  end

  @impl true
  def handle_event("select_column", %{"column" => column}, socket) do
    with {:ok, normalized_column} <- parse_non_negative_integer(column),
         :ok <- ensure_column_in_bounds(socket.assigns.record, normalized_column) do
      {:noreply,
       socket
       |> assign(:selected_column, normalized_column)
       |> assign(:selected_row, nil)
       |> assign(:selected_pad, nil)
       |> assign_keyboard_from_selected_pad()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid column selection")}
    end
  end

  @impl true
  def handle_event("insert_row_before_selected", _params, socket) do
    with row when is_integer(row) <- socket.assigns.selected_row,
         {:ok, record} <- ChordMatrices.insert_row_before(socket.assigns.record.id, row) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> adjust_selection_after_insert(:row_before, row, record)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Row inserted before selected row")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a row first")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Insert failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("insert_row_after_selected", _params, socket) do
    with row when is_integer(row) <- socket.assigns.selected_row,
         {:ok, record} <- ChordMatrices.insert_row_after(socket.assigns.record.id, row) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> adjust_selection_after_insert(:row_after, row, record)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Row inserted after selected row")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a row first")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Insert failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("move_selected_row_up", _params, socket) do
    with row when is_integer(row) <- socket.assigns.selected_row,
         true <- row > 0,
         {:ok, record} <- ChordMatrices.move_row_up(socket.assigns.record.id, row) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:selected_row, row - 1)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Moved selected row up")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Select a row first")}
      false -> {:noreply, put_flash(socket, :error, "Selected row is already at the top")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Move failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("move_selected_row_down", _params, socket) do
    with row when is_integer(row) <- socket.assigns.selected_row,
         true <- row < socket.assigns.record.chord_matrix.number_rows - 1,
         {:ok, record} <- ChordMatrices.move_row_down(socket.assigns.record.id, row) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:selected_row, row + 1)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Moved selected row down")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Select a row first")}
      false -> {:noreply, put_flash(socket, :error, "Selected row is already at the bottom")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Move failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("remove_selected_row", _params, socket) do
    with row when is_integer(row) <- socket.assigns.selected_row,
         true <- socket.assigns.record.chord_matrix.number_rows > 1,
         deleted_count <- count_assignments_in_row(socket.assigns.record, row),
         {:ok, record} <- ChordMatrices.remove_row(socket.assigns.record.id, row) do
      message =
        if deleted_count > 0,
          do: "Removed selected row (#{deleted_count} assigned pad(s) deleted)",
          else: "Removed selected row"

      {:noreply,
       socket
       |> assign(:record, record)
       |> adjust_selection_after_remove(:row, row, record)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, message)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a row first")}

      false ->
        {:noreply, put_flash(socket, :error, "Matrix must keep at least one row")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Remove failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("insert_column_left_selected", _params, socket) do
    with column when is_integer(column) <- socket.assigns.selected_column,
         {:ok, record} <- ChordMatrices.insert_column_left(socket.assigns.record.id, column) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> adjust_selection_after_insert(:column_left, column, record)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Column inserted left of selected column")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a column first")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Insert failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("insert_column_right_selected", _params, socket) do
    with column when is_integer(column) <- socket.assigns.selected_column,
         {:ok, record} <- ChordMatrices.insert_column_right(socket.assigns.record.id, column) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> adjust_selection_after_insert(:column_right, column, record)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Column inserted right of selected column")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a column first")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Insert failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("move_selected_column_left", _params, socket) do
    with column when is_integer(column) <- socket.assigns.selected_column,
         true <- column > 0,
         {:ok, record} <- ChordMatrices.move_column_left(socket.assigns.record.id, column) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:selected_column, column - 1)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Moved selected column left")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a column first")}

      false ->
        {:noreply, put_flash(socket, :error, "Selected column is already at the left edge")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Move failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("move_selected_column_right", _params, socket) do
    with column when is_integer(column) <- socket.assigns.selected_column,
         true <- column < socket.assigns.record.chord_matrix.number_columns - 1,
         {:ok, record} <- ChordMatrices.move_column_right(socket.assigns.record.id, column) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> assign(:selected_column, column + 1)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, "Moved selected column right")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a column first")}

      false ->
        {:noreply, put_flash(socket, :error, "Selected column is already at the right edge")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Move failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("remove_selected_column", _params, socket) do
    with column when is_integer(column) <- socket.assigns.selected_column,
         true <- socket.assigns.record.chord_matrix.number_columns > 1,
         deleted_count <- count_assignments_in_column(socket.assigns.record, column),
         {:ok, record} <- ChordMatrices.remove_column(socket.assigns.record.id, column) do
      message =
        if deleted_count > 0,
          do: "Removed selected column (#{deleted_count} assigned pad(s) deleted)",
          else: "Removed selected column"

      {:noreply,
       socket
       |> assign(:record, record)
       |> adjust_selection_after_remove(:column, column, record)
       |> assign_keyboard_from_selected_pad()
       |> put_flash(:info, message)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a column first")}

      false ->
        {:noreply, put_flash(socket, :error, "Matrix must keep at least one column")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Remove failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("clear_selected_pad_assignment", _params, socket) do
    case socket.assigns.selected_pad do
      {row, column} when is_integer(row) and is_integer(column) ->
        case ChordMatrices.clear_pad_assignment(socket.assigns.record.id, row, column) do
          {:ok, record} ->
            {:noreply, socket |> assign(:record, record) |> put_flash(:info, "Pad cleared")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to clear pad assignment: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Select a pad first")}
    end
  end

  @impl true
  def handle_event("toggle_progression", %{"id" => id}, socket) do
    if MapSet.member?(socket.assigns.expanded_progression_ids, id) do
      {:noreply,
       assign(
         socket,
         :expanded_progression_ids,
         MapSet.delete(socket.assigns.expanded_progression_ids, id)
       )}
    else
      case ensure_progression_loaded(socket, id) do
        {:ok, socket_with_progression} ->
          {:noreply,
           assign(
             socket_with_progression,
             :expanded_progression_ids,
             MapSet.put(socket.assigns.expanded_progression_ids, id)
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to load progression: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event(
        "assign_pad_chord",
        %{"progression_id" => progression_id, "chord_index" => chord_index},
        socket
      ) do
    with {row, column} when is_integer(row) and is_integer(column) <- socket.assigns.selected_pad,
         {:ok, progression} <- fetch_progression_for_assignment(socket, progression_id),
         {:ok, parsed_index} <- parse_non_negative_integer(chord_index),
         %ChordSpec{} = chord_spec <- Enum.at(progression.chords, parsed_index),
         {:ok, record} <-
           ChordMatrices.assign_chord_to_pad(socket.assigns.record.id, row, column, chord_spec, %{
             source_progression_id: progression_id,
             source_progression_name: progression.name,
             source_chord_index: parsed_index
           }) do
      {:noreply,
       socket
       |> assign(:record, record)
       |> put_flash(:info, "Assigned chord to pad")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Select a pad first")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Assignment failed: #{inspect(reason)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid chord assignment")}
    end
  end

  @impl true
  def handle_event(
        "assign_progression_to_selection",
        %{"progression_id" => progression_id},
        socket
      ) do
    assign_progression_to_selection(socket, progression_id, false)
  end

  @impl true
  def handle_event("cancel_bulk_assign_truncate", _params, socket) do
    {:noreply, assign(socket, :bulk_assign_confirm, nil)}
  end

  @impl true
  def handle_event("confirm_bulk_assign_truncate", _params, socket) do
    case socket.assigns.bulk_assign_confirm do
      %{progression_id: progression_id} ->
        assign_progression_to_selection(socket, progression_id, true)

      _ ->
        {:noreply, put_flash(socket, :error, "Nothing to confirm")}
    end
  end

  @impl true
  def handle_event(
        "play_progression_chord",
        %{"progression_id" => progression_id, "chord_index" => chord_index},
        socket
      ) do
    with {:ok, progression} <- fetch_progression_for_assignment(socket, progression_id),
         {:ok, parsed_index} <- parse_non_negative_integer(chord_index),
         %ChordSpec{} = chord_spec <- Enum.at(progression.chords, parsed_index) do
      play_notes_for_3s(
        socket,
        Resolver.resolve(chord_spec),
        "Previewing #{ChordSpec.symbol_label(chord_spec)}"
      )
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Preview failed: #{inspect(reason)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid chord selection")}
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
    ~H"""
    <Layouts.app flash={@flash} midi_status={@midi_status} nav_active={:chord_matrix}>
      <section class="mx-auto w-full max-w-7xl space-y-4">
        <.page_heading
          title={if @record, do: "Chord Matrix #{@record.id}", else: "Chord Matrix"}
          subtitle={if(@record, do: "Updated #{format_timestamp(@record.updated_at)}", else: "")}
        />

        <div :if={@record} class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
          <div class="space-y-3">
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <div class="flex flex-wrap items-center gap-2">
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                  Size
                </span>
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-xs text-zinc-100">
                  {@record.chord_matrix.number_rows} rows x {@record.chord_matrix.number_columns} columns
                </span>
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-xs text-zinc-100">
                  {@record.chord_matrix.bpm} BPM
                </span>
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-xs text-zinc-100">
                  Frame {@record.chord_matrix.frame_mbeats} mbeats
                </span>
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-xs text-zinc-100">
                  {@record.chord_matrix.duration_mbeats} mbeats
                </span>
                <span class="rounded-sm border border-zinc-700/70 bg-zinc-900/70 px-2 py-1 font-mono text-xs text-zinc-100">
                  TS {elem(@record.chord_matrix.time_signature, 0)}/{elem(
                    @record.chord_matrix.time_signature,
                    1
                  )}
                </span>
              </div>

              <div class="mt-3 flex flex-wrap items-end gap-4">
                <.form
                  for={@bpm_form}
                  id="matrix-bpm-form"
                  phx-submit="update_bpm"
                  class="flex flex-wrap items-end gap-2"
                >
                  <.input
                    field={@bpm_form[:bpm]}
                    type="number"
                    min="1"
                    label="BPM"
                    required
                  />

                  <button
                    id="matrix-bpm-save"
                    type="submit"
                    class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
                  >
                    Save BPM
                  </button>
                </.form>

                <.form
                  for={@frame_mbeats_form}
                  id="matrix-frame-mbeats-form"
                  phx-submit="update_frame_mbeats"
                  class="flex flex-wrap items-end gap-2"
                >
                  <.input
                    field={@frame_mbeats_form[:frame_mbeats]}
                    type="number"
                    min="1"
                    label="Frame (mbeats)"
                    required
                  />

                  <button
                    id="matrix-frame-mbeats-save"
                    type="submit"
                    class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
                  >
                    Save Frame
                  </button>
                </.form>

                <.form
                  for={@duration_form}
                  id="matrix-duration-form"
                  phx-submit="update_duration_mbeats"
                  class="flex flex-wrap items-end gap-2"
                >
                  <.input
                    field={@duration_form[:duration_mbeats]}
                    type="number"
                    min="1"
                    label="Duration (mbeats)"
                    required
                  />

                  <button
                    id="matrix-duration-save"
                    type="submit"
                    class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
                  >
                    Save Duration
                  </button>
                </.form>

                <.form
                  for={@time_signature_form}
                  id="matrix-time-signature-form"
                  phx-submit="update_time_signature"
                  class="flex flex-wrap items-end gap-2"
                >
                  <.input
                    field={@time_signature_form[:time_signature_numerator]}
                    type="number"
                    min="1"
                    label="Time Sig Numerator"
                    required
                  />

                  <.input
                    field={@time_signature_form[:time_signature_denominator]}
                    type="number"
                    min="1"
                    label="Time Sig Denominator"
                    required
                  />

                  <button
                    id="matrix-time-signature-save"
                    type="submit"
                    class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
                  >
                    Save Time Signature
                  </button>
                </.form>
              </div>

              <form
                id="matrix-machine-form"
                phx-change="set_machine_settings"
                phx-submit="save_machine_settings"
                class="mt-4 space-y-3 rounded-sm border border-zinc-700/70 bg-zinc-950/60 p-3"
              >
                <h4 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                  Global Machine
                </h4>

                <label class="space-y-1">
                  <span class="block font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                    Machine Type
                  </span>
                  <select
                    name="machine[blueprint_id]"
                    value={@machine_settings["blueprint_id"]}
                    class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                  >
                    <option
                      :for={bp <- machine_blueprint_options()}
                      value={bp.id}
                      selected={@machine_settings["blueprint_id"] == bp.id}
                    >
                      {bp.label}
                    </option>
                  </select>
                </label>

                <div :if={@machine_schema == []} class="font-mono text-xs text-zinc-400">
                  No parameters required for this machine.
                </div>

                <div :if={@machine_schema != []} class="grid gap-2 lg:grid-cols-3">
                  <div :for={field <- @machine_schema} class="space-y-1">
                    <label class="block font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                      {field.label}
                    </label>

                    <select
                      :if={field.type == :enum}
                      name={"machine[additional][#{field.name}]"}
                      value={machine_additional_value(@machine_settings, field)}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    >
                      <option
                        :for={option <- Map.get(field, :options, [])}
                        value={option.value}
                        selected={
                          machine_additional_value(@machine_settings, field) ==
                            to_string(option.value)
                        }
                      >
                        {option.label}
                      </option>
                    </select>

                    <input
                      :if={field.type in [:int, :float]}
                      name={"machine[additional][#{field.name}]"}
                      type="number"
                      min={Map.get(field, :min)}
                      max={Map.get(field, :max)}
                      step={machine_field_input_step(field)}
                      value={machine_additional_value(@machine_settings, field)}
                      class="w-full rounded-sm border border-zinc-700 bg-zinc-900/80 px-2 py-1 font-mono text-xs text-zinc-100"
                    />
                  </div>
                </div>

                <button
                  id="matrix-machine-save"
                  type="submit"
                  class="rounded-sm border border-zinc-600 bg-zinc-900/70 px-3 py-1.5 font-mono text-xs text-zinc-100 transition-colors duration-150 hover:border-zinc-400"
                >
                  Save Machine Settings
                </button>
              </form>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                  Matrix Board
                </h3>

                <div class="flex items-center gap-3">
                  <div class="flex items-center gap-1 rounded-sm border border-zinc-700/70 bg-zinc-950/70 px-1.5 py-1">
                    <span class="font-mono text-[10px] uppercase tracking-wide text-zinc-400">Row</span>
                    <button
                      id="row-insert-before"
                      type="button"
                      phx-click="insert_row_before_selected"
                      disabled={is_nil(@selected_row)}
                      title="Add row before selected row"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <span class="flex items-center gap-0.5">
                        <.icon name="hero-plus" class="size-3.5" />
                        <.icon name="hero-arrow-up" class="size-3.5" />
                      </span>
                    </button>
                    <button
                      id="row-insert-after"
                      type="button"
                      phx-click="insert_row_after_selected"
                      disabled={is_nil(@selected_row)}
                      title="Add row after selected row"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <span class="flex items-center gap-0.5">
                        <.icon name="hero-plus" class="size-3.5" />
                        <.icon name="hero-arrow-down" class="size-3.5" />
                      </span>
                    </button>
                    <button
                      id="row-move-up"
                      type="button"
                      phx-click="move_selected_row_up"
                      disabled={is_nil(@selected_row) or @selected_row == 0}
                      title="Move selected row up"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-chevron-double-up" class="size-4" />
                    </button>
                    <button
                      id="row-move-down"
                      type="button"
                      phx-click="move_selected_row_down"
                      disabled={
                        is_nil(@selected_row) or @selected_row >= @record.chord_matrix.number_rows - 1
                      }
                      title="Move selected row down"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-chevron-double-down" class="size-4" />
                    </button>
                    <button
                      id="row-remove"
                      type="button"
                      phx-click="remove_selected_row"
                      disabled={is_nil(@selected_row) or @record.chord_matrix.number_rows <= 1}
                      title="Remove selected row"
                      class="rounded-sm border border-rose-700/80 bg-rose-900/20 p-1 text-rose-200 transition-colors duration-150 enabled:hover:border-rose-500 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-minus" class="size-4" />
                    </button>
                  </div>

                  <div class="flex items-center gap-1 rounded-sm border border-zinc-700/70 bg-zinc-950/70 px-1.5 py-1">
                    <span class="font-mono text-[10px] uppercase tracking-wide text-zinc-400">Column</span>
                    <button
                      id="column-insert-left"
                      type="button"
                      phx-click="insert_column_left_selected"
                      disabled={is_nil(@selected_column)}
                      title="Add column left of selected column"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <span class="flex items-center gap-0.5">
                        <.icon name="hero-plus" class="size-3.5" />
                        <.icon name="hero-arrow-left" class="size-3.5" />
                      </span>
                    </button>
                    <button
                      id="column-insert-right"
                      type="button"
                      phx-click="insert_column_right_selected"
                      disabled={is_nil(@selected_column)}
                      title="Add column right of selected column"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <span class="flex items-center gap-0.5">
                        <.icon name="hero-plus" class="size-3.5" />
                        <.icon name="hero-arrow-right" class="size-3.5" />
                      </span>
                    </button>
                    <button
                      id="column-move-left"
                      type="button"
                      phx-click="move_selected_column_left"
                      disabled={is_nil(@selected_column) or @selected_column == 0}
                      title="Move selected column left"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-chevron-double-left" class="size-4" />
                    </button>
                    <button
                      id="column-move-right"
                      type="button"
                      phx-click="move_selected_column_right"
                      disabled={
                        is_nil(@selected_column) or
                          @selected_column >= @record.chord_matrix.number_columns - 1
                      }
                      title="Move selected column right"
                      class="rounded-sm border border-zinc-600/80 bg-zinc-900/70 p-1 text-zinc-100 transition-colors duration-150 enabled:hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-chevron-double-right" class="size-4" />
                    </button>
                    <button
                      id="column-remove"
                      type="button"
                      phx-click="remove_selected_column"
                      disabled={is_nil(@selected_column) or @record.chord_matrix.number_columns <= 1}
                      title="Remove selected column"
                      class="rounded-sm border border-rose-700/80 bg-rose-900/20 p-1 text-rose-200 transition-colors duration-150 enabled:hover:border-rose-500 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-minus" class="size-4" />
                    </button>
                  </div>

                  <div class="flex items-center gap-2">
                    <button
                      id="toggle-matrix-play-mode"
                      type="button"
                      phx-click="toggle_matrix_play_mode"
                      role="switch"
                      aria-checked={to_string(@chord_matrix_play_mode)}
                      class="group inline-flex items-center gap-2 rounded-sm border border-zinc-600/80 bg-zinc-900/70 px-2 py-1.5 transition-colors duration-150 hover:border-zinc-400"
                    >
                      <span class="font-mono text-[10px] uppercase tracking-wide text-zinc-200">Play Mode</span>
                      <span class={[
                        "relative h-4 w-8 rounded-full border transition-colors duration-200",
                        if(@chord_matrix_play_mode,
                          do: "border-emerald-300/90 bg-emerald-500/60",
                          else: "border-zinc-500/80 bg-zinc-800"
                        )
                      ]}>
                        <span class={[
                          "absolute top-0.5 size-2.5 rounded-full bg-zinc-100 transition-transform duration-200",
                          if(@chord_matrix_play_mode, do: "translate-x-4", else: "translate-x-0.5")
                        ]}></span>
                      </span>
                    </button>
                  </div>
                </div>
              </div>

              <div class="mt-3 space-y-2 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2">
                <div class="flex items-center justify-between gap-2">
                  <h4 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                    Active Chord Keyboard
                  </h4>
                  <p class="truncate font-mono text-[11px] text-zinc-400">{@keyboard_source}</p>
                </div>

                <FullPianoKeyboard.keyboard
                  id="chord-matrix-active-keyboard"
                  keys={piano_keys(@keyboard_active_notes)}
                  height_class="h-28"
                  show_bottom_lane={false}
                  color_mode={:dark}
                />
              </div>

              <div
                id="pad-mpe-detail-panel"
                class="mt-3 space-y-2 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2"
              >
                <div class="flex items-center justify-between gap-2">
                  <div class="flex items-center gap-2">
                    <h4 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                      Detail MPE Data
                    </h4>
                    <p
                      :if={@latest_pad_performance && @show_detail_mpe_data}
                      class="font-mono text-[10px] text-zinc-400"
                    >
                      {@latest_pad_performance.bpm} BPM · {elem(
                        @latest_pad_performance.time_signature,
                        0
                      )}/{elem(@latest_pad_performance.time_signature, 1)}
                    </p>
                  </div>

                  <button
                    id="toggle-display-detail-mpe-data"
                    type="button"
                    phx-click="toggle_display_detail_mpe_data"
                    role="switch"
                    aria-checked={to_string(@show_detail_mpe_data)}
                    class="group inline-flex items-center gap-2 rounded-sm border border-zinc-700/80 bg-zinc-900/60 px-2 py-1 transition-colors duration-150 hover:border-zinc-500"
                  >
                    <span class="font-mono text-[10px] uppercase tracking-wide text-zinc-300">Show MPE Charts</span>
                    <span class={[
                      "relative h-4 w-8 rounded-full border transition-colors duration-200",
                      if(@show_detail_mpe_data,
                        do: "border-emerald-300/90 bg-emerald-500/60",
                        else: "border-zinc-500/80 bg-zinc-800"
                      )
                    ]}>
                      <span class={[
                        "absolute top-0.5 size-2.5 rounded-full bg-zinc-100 transition-transform duration-200",
                        if(@show_detail_mpe_data, do: "translate-x-4", else: "translate-x-0.5")
                      ]}></span>
                    </span>
                  </button>
                </div>

                <div
                  :if={not @show_detail_mpe_data}
                  class="rounded-sm border border-zinc-700/60 bg-zinc-950/80 p-2 font-mono text-xs text-zinc-400"
                >
                  MPE charts are hidden. Toggle "Show MPE Charts" to display them.
                </div>

                <div
                  :if={
                    @show_detail_mpe_data and
                      @note_matrix == [] and
                      @pressure_chart == [] and @slide_chart == [] and @bend_chart == []
                  }
                  class="rounded-sm border border-zinc-700/60 bg-zinc-950/80 p-2 font-mono text-xs text-zinc-400"
                >
                  Click an assigned pad while play mode is on to render expression charts.
                </div>

                <div
                  :if={
                    @show_detail_mpe_data and
                      (@note_matrix != [] or
                         @pressure_chart != [] or @slide_chart != [] or @bend_chart != [])
                  }
                  class="space-y-2"
                >
                  <.note_matrix_chart note_matrix={@note_matrix} grid={@note_matrix_grid} />
                  <.mpe_chart
                    title="Pressure"
                    chart={@pressure_chart}
                    grid={@chart_grid}
                    axis={@pressure_axis}
                  />
                  <.mpe_chart
                    title="Slide (Aftertouch)"
                    chart={@slide_chart}
                    grid={@chart_grid}
                    axis={@slide_axis}
                  />
                  <.mpe_chart
                    title="Bend (Vibrato)"
                    chart={@bend_chart}
                    grid={@chart_grid}
                    axis={@bend_axis}
                  />
                </div>
              </div>

              <div class="mt-3 overflow-x-auto">
                <div
                  id="chord-matrix-board"
                  class="inline-grid gap-1"
                  style={
                    "grid-template-columns: 2rem repeat(#{@record.chord_matrix.number_columns}, minmax(0, 6rem));"
                  }
                >
                  <div class="h-8"></div>

                  <button
                    :for={col <- 0..(@record.chord_matrix.number_columns - 1)}
                    id={"column-header-#{col}"}
                    type="button"
                    phx-click="select_column"
                    phx-value-column={col}
                    title={"Select column #{col + 1}"}
                    class={column_header_classes(@selected_column == col)}
                  >
                    C{col + 1}
                  </button>

                  <div :for={row <- 0..(@record.chord_matrix.number_rows - 1)} class="contents">
                    <button
                      id={"row-header-#{row}"}
                      type="button"
                      phx-click="select_row"
                      phx-value-row={row}
                      title={"Select row #{row + 1}"}
                      class={row_header_classes(@selected_row == row)}
                    >
                      R{row + 1}
                    </button>

                    <button
                      :for={col <- 0..(@record.chord_matrix.number_columns - 1)}
                      id={"pad-#{row}-#{col}"}
                      type="button"
                      phx-click="select_pad"
                      phx-value-row={row}
                      phx-value-column={col}
                      class={
                        pad_cell_classes(
                          @selected_pad == {row, col},
                          pad_assignment(@record, row, col) != nil
                        )
                      }
                    >
                      <%= if @selected_pad != {row, col} do %>
                        <span
                          :if={@selected_row == row and @selected_column == col}
                          class="pointer-events-none absolute inset-0 rounded-[inherit] bg-[var(--cm-pad-intersection-cue)] cm-pad-intersection-pulse"
                        ></span>
                        <span
                          :if={@selected_row == row and @selected_column != col}
                          class="pointer-events-none absolute inset-0 rounded-[inherit] bg-[var(--cm-pad-row-cue)]"
                        ></span>
                        <span
                          :if={@selected_column == col and @selected_row != row}
                          class="pointer-events-none absolute inset-0 rounded-[inherit] bg-[var(--cm-pad-column-cue)]"
                        ></span>
                      <% end %>

                      <%= case pad_assignment(@record, row, col) do %>
                        <% nil -> %>
                          <span class="relative z-10 flex h-full w-full items-center justify-center font-mono text-[10px] text-zinc-500">
                            {row},{col}
                          </span>
                        <% assignment -> %>
                          <span class="relative z-10 flex h-full w-full items-center justify-center">
                            <span class="w-full truncate text-center font-mono text-base font-semibold leading-none tracking-tight text-inherit">
                              {ChordSpec.symbol_label(assignment.chord_spec)}
                            </span>
                          </span>
                      <% end %>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <aside class="space-y-3">
            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                Selected Pad
              </h3>

              <%= case @selected_pad do %>
                <% {row, column} -> %>
                  <p class="mt-2 font-mono text-xs text-zinc-200">
                    Row {row + 1}, Column {column + 1}
                  </p>

                  <%= case pad_assignment(@record, row, column) do %>
                    <% nil -> %>
                      <p class="mt-2 font-mono text-xs text-zinc-400">No chord assigned.</p>
                    <% assignment -> %>
                      <div class="mt-2 space-y-1 rounded-sm border border-zinc-700/70 bg-zinc-950/70 p-2">
                        <p class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">
                          Chord Spec
                        </p>
                        <p class="font-mono text-xs text-zinc-200">
                          {ChordSpec.symbol_label(assignment.chord_spec)}
                        </p>
                      </div>

                      <button
                        type="button"
                        phx-click="clear_selected_pad_assignment"
                        class="mt-2 rounded-sm border border-rose-700/80 bg-rose-900/20 px-2.5 py-1.5 font-mono text-[11px] text-rose-200 transition-colors duration-150 hover:border-rose-500"
                      >
                        Clear Pad
                      </button>
                  <% end %>
                <% nil -> %>
                  <p class="mt-2 font-mono text-xs text-zinc-400">Select a pad on the board.</p>
              <% end %>
            </div>

            <div class="rounded-sm border border-zinc-700/70 bg-zinc-950/50 p-3">
              <h3 class="font-mono text-[11px] uppercase tracking-wide text-zinc-300">
                Chord Progressions
              </h3>

              <div
                :if={@progressions == []}
                class="mt-2 rounded-sm border border-zinc-700/60 bg-zinc-950/70 p-2"
              >
                <p class="font-mono text-xs text-zinc-400">No stored progressions found.</p>
              </div>

              <div :if={@progressions != []} class="mt-2 space-y-2">
                <div
                  :for={item <- @progressions}
                  class="rounded-sm border border-zinc-700/70 bg-zinc-950/70"
                >
                  <button
                    id={"toggle-progression-#{item.id}"}
                    type="button"
                    phx-click="toggle_progression"
                    phx-value-id={item.id}
                    class="flex w-full items-center justify-between px-2.5 py-2 text-left"
                  >
                    <span class="min-w-0 truncate font-mono text-xs text-zinc-100">{item.name}</span>
                    <span class="font-mono text-[10px] text-zinc-400">
                      {if MapSet.member?(@expanded_progression_ids, item.id), do: "Hide", else: "Show"}
                    </span>
                  </button>

                  <div
                    :if={MapSet.member?(@expanded_progression_ids, item.id)}
                    class="border-t border-zinc-700/60 px-2 py-2"
                  >
                    <%= case Map.get(@progression_records, item.id) do %>
                      <% nil -> %>
                        <p class="font-mono text-xs text-zinc-400">Unable to load progression.</p>
                      <% progression_record -> %>
                        <div class="space-y-1.5">
                          <button
                            id={"assign-sequence-#{item.id}"}
                            type="button"
                            phx-click="assign_progression_to_selection"
                            phx-value-progression_id={item.id}
                            disabled={is_nil(axis_selection(@selected_row, @selected_column))}
                            class="w-full rounded-sm border border-amber-500/80 bg-amber-900/20 px-2 py-1.5 text-left font-mono text-[10px] uppercase tracking-wide text-amber-100 transition-colors duration-150 enabled:hover:border-amber-300 disabled:cursor-not-allowed disabled:opacity-40"
                          >
                            {assign_selection_button_label(@selected_row, @selected_column)}
                          </button>

                          <div
                            :for={
                              {chord_spec, chord_index} <-
                                Enum.with_index(progression_record.progression.chords)
                            }
                            class="flex items-center gap-1 rounded-sm border border-zinc-700/60 bg-zinc-900/70 p-1"
                          >
                            <button
                              type="button"
                              phx-click="play_progression_chord"
                              phx-value-progression_id={item.id}
                              phx-value-chord_index={chord_index}
                              class="rounded-sm border border-emerald-600/80 bg-emerald-800/20 px-1.5 py-1 font-mono text-[10px] text-emerald-100 transition-colors duration-150 hover:border-emerald-400"
                            >
                              Play
                            </button>

                            <span class="min-w-0 flex-1 truncate font-mono text-[11px] text-zinc-100">
                              {ChordSpec.symbol_label(chord_spec)}
                            </span>

                            <button
                              id={"assign-#{item.id}-#{chord_index}"}
                              type="button"
                              phx-click="assign_pad_chord"
                              phx-value-progression_id={item.id}
                              phx-value-chord_index={chord_index}
                              disabled={is_nil(@selected_pad)}
                              class="rounded-sm border border-sky-500/80 bg-sky-900/20 px-1.5 py-1 font-mono text-[10px] text-sky-100 transition-colors duration-150 enabled:hover:border-sky-300 disabled:cursor-not-allowed disabled:opacity-40"
                            >
                              Assign
                            </button>
                          </div>
                        </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </aside>
        </div>

        <%= if @bulk_assign_confirm do %>
          <div
            id="bulk-assign-modal"
            class="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/70 px-4"
          >
            <div class="w-full max-w-md rounded-sm border border-zinc-600 bg-zinc-900 p-4 shadow-2xl">
              <h4 class="font-mono text-sm text-zinc-100">Confirm Truncated Assignment</h4>
              <p class="mt-2 font-mono text-xs text-zinc-300">
                {truncate_confirmation_message(@bulk_assign_confirm)}
              </p>

              <div class="mt-3 flex items-center justify-end gap-2">
                <button
                  id="bulk-assign-cancel"
                  type="button"
                  phx-click="cancel_bulk_assign_truncate"
                  class="rounded-sm border border-zinc-600 px-2.5 py-1.5 font-mono text-[11px] text-zinc-200 transition-colors duration-150 hover:border-zinc-400"
                >
                  Cancel
                </button>
                <button
                  id="bulk-assign-confirm"
                  type="button"
                  phx-click="confirm_bulk_assign_truncate"
                  class="rounded-sm border border-amber-500/90 bg-amber-900/30 px-2.5 py-1.5 font-mono text-[11px] text-amber-100 transition-colors duration-150 hover:border-amber-300"
                >
                  Assign Available Pads
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp axis_selection(selected_row, selected_column) do
    cond do
      is_integer(selected_row) -> {:row, selected_row}
      is_integer(selected_column) -> {:column, selected_column}
      true -> nil
    end
  end

  defp assign_selection_button_label(selected_row, selected_column) do
    case axis_selection(selected_row, selected_column) do
      {:row, row} -> "Assign Full Progression To Row #{row + 1}"
      {:column, column} -> "Assign Full Progression To Column #{column + 1}"
      nil -> "Select a row or column first"
    end
  end

  defp truncate_confirmation_message(%{
         progression_name: progression_name,
         target_label: target_label,
         total_chords: total_chords,
         capacity: capacity
       }) do
    overflow_count = max(total_chords - capacity, 0)

    "#{progression_name} has #{total_chords} chords but #{target_label} only has #{capacity} pads. " <>
      "Proceed and assign the first #{capacity} chords only? The last #{overflow_count} chords will be skipped."
  end

  defp assign_progression_to_selection(socket, progression_id, force_truncate?) do
    case axis_selection(socket.assigns.selected_row, socket.assigns.selected_column) do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a row or column first")}

      {axis, axis_index} ->
        with {:ok, progression} <- fetch_progression_for_assignment(socket, progression_id) do
          capacity = axis_capacity(socket.assigns.record, axis)
          total_chords = length(progression.chords)

          cond do
            total_chords > capacity and not force_truncate? ->
              target_label = axis_target_label(axis, axis_index)

              {:noreply,
               assign(socket, :bulk_assign_confirm, %{
                 progression_id: progression_id,
                 progression_name: progression.name,
                 target_label: target_label,
                 total_chords: total_chords,
                 capacity: capacity
               })}

            true ->
              persist_progression_assignment(
                socket,
                progression_id,
                progression,
                axis,
                axis_index,
                total_chords,
                capacity
              )
          end
        else
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Assignment failed: #{inspect(reason)}")}
        end
    end
  end

  defp persist_progression_assignment(
         socket,
         progression_id,
         progression,
         axis,
         axis_index,
         total_chords,
         capacity
       ) do
    result =
      case axis do
        :row ->
          ChordMatrices.assign_progression_to_row(
            socket.assigns.record.id,
            axis_index,
            progression_id,
            progression.name,
            progression.chords
          )

        :column ->
          ChordMatrices.assign_progression_to_column(
            socket.assigns.record.id,
            axis_index,
            progression_id,
            progression.name,
            progression.chords
          )
      end

    case result do
      {:ok, record} ->
        assigned_count = min(total_chords, capacity)
        skipped_count = max(total_chords - capacity, 0)
        target_label = axis_target_label(axis, axis_index)

        message =
          if skipped_count > 0 do
            "Assigned #{assigned_count} chord(s) to #{target_label}. Skipped #{skipped_count} trailing chord(s)."
          else
            "Assigned #{assigned_count} chord(s) to #{target_label}."
          end

        {:noreply,
         socket
         |> assign(:record, record)
         |> assign(:bulk_assign_confirm, nil)
         |> assign_keyboard_from_selected_pad()
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Assignment failed: #{inspect(reason)}")}
    end
  end

  defp axis_capacity(record, :row), do: record.chord_matrix.number_columns
  defp axis_capacity(record, :column), do: record.chord_matrix.number_rows

  defp axis_target_label(:row, axis_index), do: "selected row #{axis_index + 1}"
  defp axis_target_label(:column, axis_index), do: "selected column #{axis_index + 1}"

  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_non_negative_integer(_value), do: {:error, :invalid_integer}

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_integer}

  defp maybe_refresh_detail_mpe_data(socket) do
    cond do
      not socket.assigns.show_detail_mpe_data ->
        socket

      not match?({row, col} when is_integer(row) and is_integer(col), socket.assigns.selected_pad) ->
        clear_detail_mpe_data(socket)

      true ->
        {row, col} = socket.assigns.selected_pad

        case ChordMatrixPadPlayer.performance_for_pad(socket.assigns.record, row, col) do
          {:ok, performance} -> assign_detail_mpe_data(socket, performance)
          _ -> clear_detail_mpe_data(socket)
        end
    end
  end

  defp maybe_assign_detail_mpe_data(socket, performance) do
    if socket.assigns.show_detail_mpe_data do
      assign_detail_mpe_data(socket, performance)
    else
      socket
    end
  end

  defp assign_detail_mpe_data(socket, %{frames: frames, duration_ms: duration_ms} = performance) do
    frame_mbeats = socket.assigns.record.chord_matrix.frame_mbeats

    sample_context =
      SampleContext.new!(%{
        bpm: performance.bpm,
        time_signature: performance.time_signature,
        frame_mbeats: frame_mbeats
      })

    total_mbeats = detail_total_mbeats(frames, duration_ms, sample_context)
    color_map = note_color_map(frames)
    bend_range = value_range(frames)

    socket
    |> assign(:latest_pad_performance, performance)
    |> assign(:note_matrix, build_note_matrix(frames, color_map, total_mbeats))
    |> assign(:note_matrix_grid, note_matrix_grid_model(sample_context, total_mbeats))
    |> assign(
      :pressure_chart,
      build_mpe_chart(frames, :pressure, {0, 127}, color_map, total_mbeats)
    )
    |> assign(:slide_chart, build_mpe_chart(frames, :slide, {0, 127}, color_map, total_mbeats))
    |> assign(:bend_chart, build_mpe_chart(frames, :bend, bend_range, color_map, total_mbeats))
    |> assign(:pressure_axis, pressure_slide_axis())
    |> assign(:slide_axis, pressure_slide_axis())
    |> assign(:bend_axis, bend_axis(bend_range))
    |> assign(:chart_grid, chart_grid_model(sample_context, total_mbeats))
  end

  defp assign_detail_mpe_data(socket, _performance), do: clear_detail_mpe_data(socket)

  defp clear_detail_mpe_data(socket) do
    socket
    |> assign(:latest_pad_performance, nil)
    |> assign(:note_matrix, [])
    |> assign(:note_matrix_grid, %{subbeat_pcts: [], beat_pcts: [], bar_pcts: []})
    |> assign(:pressure_chart, [])
    |> assign(:slide_chart, [])
    |> assign(:bend_chart, [])
    |> assign(:pressure_axis, pressure_slide_axis())
    |> assign(:slide_axis, pressure_slide_axis())
    |> assign(:bend_axis, bend_axis({-1.0, 1.0}))
    |> assign(:chart_grid, %{subbeat_xs: [], beat_xs: [], bar_xs: []})
  end

  defp bpm_form(value) do
    to_form(%{"bpm" => to_string(value)}, as: :chord_matrix)
  end

  defp duration_form(value) do
    to_form(%{"duration_mbeats" => to_string(value)}, as: :chord_matrix)
  end

  defp frame_mbeats_form(value) do
    to_form(%{"frame_mbeats" => to_string(value)}, as: :chord_matrix)
  end

  defp time_signature_form({num, den}) do
    to_form(
      %{
        "time_signature_numerator" => to_string(num),
        "time_signature_denominator" => to_string(den)
      },
      as: :chord_matrix
    )
  end

  defp time_signature_form(%{"numerator" => num, "denominator" => den}) do
    to_form(
      %{
        "time_signature_numerator" => to_string(num),
        "time_signature_denominator" => to_string(den)
      },
      as: :chord_matrix
    )
  end

  defp machine_blueprint_options do
    SampleBlueprint.available_blueprints()
  end

  defp machine_additional_value(settings, field) do
    additional = Map.get(settings, "additional", %{})
    value = Map.get(additional, field.name, field.default)
    to_string(value)
  end

  defp machine_field_input_step(%{type: :int}), do: "1"

  defp machine_field_input_step(%{type: :float} = field),
    do: to_string(Map.get(field, :step, 0.1))

  defp detail_total_mbeats(frames, duration_ms, %SampleContext{} = sample_context) do
    mbeat_by_duration = SampleContext.ms_to_mbeats(sample_context, duration_ms)
    mbeat_by_frames = frames |> List.last() |> then(&if(&1, do: &1.at_mbeat, else: 0))
    max(max(mbeat_by_duration, mbeat_by_frames), 1)
  end

  defp chart_grid_model(%SampleContext{} = sample_context, total_mbeats) do
    width = 600
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    mbeats_per_subbeat = max(div(mbeats_per_beat, 4), 1)
    total_mbeats = max(total_mbeats, 1)

    %{
      subbeat_xs: chart_grid_xs(total_mbeats, mbeats_per_subbeat, width),
      beat_xs: chart_grid_xs(total_mbeats, mbeats_per_beat, width),
      bar_xs: chart_grid_xs(total_mbeats, mbeats_per_bar, width)
    }
  end

  defp note_matrix_grid_model(%SampleContext{} = sample_context, total_mbeats) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)
    mbeats_per_beat = SampleContext.mbeats_per_beat(sample_context)
    mbeats_per_subbeat = max(div(mbeats_per_beat, 4), 1)
    total_mbeats = max(total_mbeats, 1)

    %{
      subbeat_pcts: timeline_pct_marks(total_mbeats, mbeats_per_subbeat),
      beat_pcts: timeline_pct_marks(total_mbeats, mbeats_per_beat),
      bar_pcts: timeline_pct_marks(total_mbeats, mbeats_per_bar)
    }
  end

  defp timeline_pct_marks(total_mbeats, step) do
    0..total_mbeats//step
    |> Enum.map(fn mbeat -> Float.round(mbeat / total_mbeats * 100, 3) end)
  end

  defp chart_grid_xs(total_mbeats, step, width) do
    0..total_mbeats//step
    |> Enum.map(fn mbeat -> Float.round(mbeat / total_mbeats * width, 2) end)
  end

  defp build_mpe_chart(frames, value_key, {min_v, max_v}, color_map, total_mbeats) do
    total_mbeats = max(total_mbeats, 1)

    frames
    |> Enum.flat_map(fn frame ->
      x = max(frame.at_mbeat, 0) / total_mbeats * 600

      Enum.map(frame.notes, fn note ->
        {note_series_key(note), x, Map.fetch!(note, value_key)}
      end)
    end)
    |> Enum.group_by(fn {series_key, _x, _value} -> series_key end, fn {_series_key, x, value} ->
      {x, value}
    end)
    |> Enum.map(fn {series_key, points} ->
      %{
        series_key: series_key,
        color: Map.fetch!(color_map, series_key),
        points: chart_points(points, min_v, max_v)
      }
    end)
    |> Enum.sort_by(& &1.series_key)
  end

  defp note_color_map(frames) do
    frames
    |> Enum.flat_map(& &1.notes)
    |> Enum.uniq_by(&note_series_key/1)
    |> Enum.sort_by(&note_series_key/1)
    |> Enum.with_index()
    |> Map.new(fn {note, index} ->
      {note_series_key(note), Enum.at(@mpe_chart_colors, rem(index, length(@mpe_chart_colors)))}
    end)
  end

  defp build_note_matrix(frames, color_map, total_mbeats) do
    total_mbeats = max(total_mbeats, 1)

    segments =
      frames
      |> Enum.flat_map(fn frame ->
        Enum.map(frame.notes, &{&1, frame.at_mbeat})
      end)
      |> Enum.group_by(fn {note, _at_mbeat} -> note_series_key(note) end)
      |> Enum.flat_map(fn {series_key, entries} ->
        {channel, midi_note_number} = series_channel_note(series_key)

        entries
        |> lifecycle_segments(total_mbeats)
        |> Enum.map(fn %{start_mbeat: start_mbeat, end_mbeat: end_mbeat, label: label} ->
          left_pct = start_mbeat / total_mbeats * 100
          width_pct = max((end_mbeat - start_mbeat) / total_mbeats * 100, 0.5)

          style =
            "left: #{Float.round(left_pct * 1.0, 2)}%; " <>
              "width: #{Float.round(width_pct * 1.0, 2)}%; " <>
              "background-color: #{Map.fetch!(color_map, series_key)};"

          %{
            style: style,
            channel: channel,
            midi_note: midi_note_number,
            label: label
          }
        end)
      end)

    case segments do
      [] ->
        []

      _ ->
        rows_by_note = Enum.group_by(segments, & &1.midi_note)
        {min_note, max_note} = rows_by_note |> Map.keys() |> Enum.min_max()

        for note_number <- max_note..min_note//-1 do
          case Map.get(rows_by_note, note_number) do
            nil ->
              {note_name, octave} = PerformanceAssembler.note_name(note_number)

              %{
                midi_note: note_number,
                label: "#{note_name}#{octave}",
                segments: []
              }

            note_segments ->
              %{
                midi_note: note_number,
                label: note_segments |> hd() |> Map.fetch!(:label),
                segments: Enum.map(note_segments, &%{style: &1.style})
              }
          end
        end
    end
  end

  defp lifecycle_segments(entries, total_mbeats) do
    {segments, open_segment} =
      entries
      |> Enum.sort_by(fn {_note, at_mbeat} -> at_mbeat end)
      |> Enum.reduce({[], nil}, fn {note, at_mbeat}, {acc, open} ->
        label = note_label(note)

        cond do
          note.note_on and is_nil(open) ->
            {acc, %{start_mbeat: at_mbeat, label: label}}

          note.note_on and not is_nil(open) ->
            closed = Map.put(open, :end_mbeat, at_mbeat)
            {[closed | acc], %{start_mbeat: at_mbeat, label: label}}

          note.note_off and not is_nil(open) ->
            closed = Map.put(open, :end_mbeat, at_mbeat)
            {[closed | acc], nil}

          true ->
            {acc, open}
        end
      end)

    segments =
      if is_nil(open_segment) do
        segments
      else
        [Map.put(open_segment, :end_mbeat, total_mbeats) | segments]
      end

    segments
    |> Enum.reverse()
    |> Enum.filter(fn segment -> segment.end_mbeat >= segment.start_mbeat end)
  end

  defp note_label(note) do
    cond do
      is_atom(Map.get(note, :note_name)) and is_integer(Map.get(note, :octave)) ->
        "#{Map.get(note, :note_name)}#{Map.get(note, :octave)}"

      is_integer(Map.get(note, :midi_note)) ->
        {note_name, octave} = PerformanceAssembler.note_name(Map.get(note, :midi_note))
        "#{note_name}#{octave}"

      true ->
        "note"
    end
  end

  defp series_channel_note({channel, note, _note_instance_id}), do: {channel, note}

  defp note_series_key(note) do
    {
      Map.get(note, :channel, -1),
      Map.get(note, :midi_note, 0),
      Map.get(note, :note_instance_id, 0)
    }
  end

  defp chart_points(points, min_v, max_v) do
    range = max(max_v - min_v, 0.0001)

    points
    |> Enum.sort_by(fn {x, _value} -> x end)
    |> Enum.map_join(" ", fn {x, value} ->
      y = @mpe_chart_height - (value - min_v) / range * @mpe_chart_height
      "#{Float.round(x * 1.0, 1)},#{Float.round(y * 1.0, 1)}"
    end)
  end

  defp pressure_slide_axis do
    %{
      min: 0,
      max: 127,
      ticks: [
        %{value: 0, label: "0"},
        %{value: 32, label: "32"},
        %{value: 64, label: "64"},
        %{value: 96, label: "96"},
        %{value: 127, label: "127"}
      ]
    }
  end

  defp bend_axis({min_v, max_v}) do
    steps = 4

    ticks =
      for step_index <- 0..steps do
        value = min_v + (max_v - min_v) * (step_index / steps)
        %{value: value, label: format_bend_tick(value)}
      end

    %{min: min_v, max: max_v, ticks: ticks}
  end

  defp value_range(frames) do
    values = for frame <- frames, note <- frame.notes, do: note.bend

    case Enum.min_max(values) do
      {same, same} -> {same - 0.0001, same + 0.0001}
      {min_v, max_v} -> {min_v, max_v}
    end
  end

  defp format_bend_tick(value) when is_number(value) do
    value
    |> Float.round(4)
    |> :erlang.float_to_binary(decimals: 4)
    |> String.replace(~r/0+$/, "")
    |> String.replace(~r/\.$/, "")
  end

  attr :note_matrix, :list, required: true
  attr :grid, :map, required: true

  defp note_matrix_chart(assigns) do
    ~H"""
    <div id="note-matrix" class="space-y-1">
      <div class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">Note matrix</div>
      <div class="relative py-1.5">
        <div
          :for={x <- @grid.subbeat_pcts}
          class="pointer-events-none absolute inset-y-0 z-0 w-px bg-zinc-700/30"
          style={"left: #{x}%;"}
        >
        </div>
        <div
          :for={x <- @grid.beat_pcts}
          class="pointer-events-none absolute inset-y-0 z-0 w-px bg-zinc-500/40"
          style={"left: #{x}%;"}
        >
        </div>
        <div
          :for={x <- @grid.bar_pcts}
          class="pointer-events-none absolute inset-y-0 z-0 w-[1.5px] bg-zinc-200/50"
          style={"left: #{x}%;"}
        >
        </div>
        <div
          :for={{row, index} <- Enum.with_index(@note_matrix)}
          class={[
            "relative z-10 flex h-2.5 items-center border-b border-zinc-700/60 last:border-0",
            rem(index, 2) == 0 && "bg-zinc-900/70"
          ]}
        >
          <div
            :for={segment <- row.segments}
            class="absolute inset-y-0 z-20 opacity-85"
            style={segment.style}
          >
          </div>
          <span class="relative z-10 px-1 font-mono text-[5px] uppercase text-zinc-400">
            {row.label}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :chart, :list, required: true
  attr :grid, :map, required: true
  attr :axis, :map, required: true

  defp mpe_chart(assigns) do
    ~H"""
    <div>
      <div class="font-mono text-[11px] uppercase tracking-wide text-zinc-400">{@title}</div>
      <svg viewBox={"0 0 600 #{mpe_chart_height()}"} class="w-full overflow-visible bg-zinc-950">
        <line
          :for={x <- @grid.subbeat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={mpe_chart_height()}
          stroke="var(--ui-chart-x-gridline-color)"
          stroke-opacity="var(--ui-chart-x-gridline-opacity)"
          stroke-width="var(--ui-chart-x-gridline-width)"
        />
        <line
          :for={x <- @grid.beat_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={mpe_chart_height()}
          stroke="var(--ui-chart-x-beat-gridline-color)"
          stroke-opacity="var(--ui-chart-x-beat-gridline-opacity)"
          stroke-width="var(--ui-chart-x-beat-gridline-width)"
        />
        <line
          :for={x <- @grid.bar_xs}
          x1={x}
          y1="0"
          x2={x}
          y2={mpe_chart_height()}
          stroke="var(--ui-chart-x-bar-gridline-color)"
          stroke-opacity="var(--ui-chart-x-bar-gridline-opacity)"
          stroke-width="var(--ui-chart-x-bar-gridline-width)"
        />
        <polyline
          :for={series <- @chart}
          points={series.points}
          fill="none"
          stroke={series.color}
          stroke-width="1.5"
        />
        <line
          x1="0"
          y1="0"
          x2="0"
          y2={mpe_chart_height()}
          stroke="#d4d4d8"
          stroke-opacity="0.85"
          stroke-width="1.1"
        />
        <line
          :for={tick <- @axis.ticks}
          x1="0"
          y1={chart_y_for_value(tick.value, @axis.min, @axis.max)}
          x2="600"
          y2={chart_y_for_value(tick.value, @axis.min, @axis.max)}
          stroke="var(--ui-chart-y-gridline-color)"
          stroke-opacity="var(--ui-chart-y-gridline-opacity)"
          stroke-width="var(--ui-chart-y-gridline-width)"
        />
        <line
          :for={tick <- @axis.ticks}
          x1="0"
          y1={chart_y_for_value(tick.value, @axis.min, @axis.max)}
          x2="6"
          y2={chart_y_for_value(tick.value, @axis.min, @axis.max)}
          stroke="#d4d4d8"
          stroke-opacity="0.8"
          stroke-width="1"
        />
        <text
          :for={tick <- @axis.ticks}
          class="ui-chart-tick-label"
          x="8"
          y={chart_y_for_value(tick.value, @axis.min, @axis.max)}
          fill="#d4d4d8"
          dominant-baseline="middle"
          font-family="ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, Liberation Mono, Courier New, monospace"
        >
          {tick.label}
        </text>
      </svg>
    </div>
    """
  end

  defp chart_y_for_value(value, min_v, max_v) do
    range = max(max_v - min_v, 0.0001)
    @mpe_chart_height - (value - min_v) / range * @mpe_chart_height
  end

  defp mpe_chart_height, do: @mpe_chart_height

  defp default_machine_settings do
    blueprint_id = SampleBlueprint.default_blueprint_id()

    additional =
      case SampleBlueprint.default_additional_params(blueprint_id) do
        {:ok, values} -> normalize_map_string_keys(values)
        {:error, _reason} -> %{}
      end

    %{"blueprint_id" => blueprint_id, "additional" => additional}
  end

  defp normalize_machine_settings(blueprint_id, additional) when is_binary(blueprint_id) do
    normalized_additional = normalize_map_string_keys(additional)

    with {:ok, schema} <- SampleBlueprint.additional_param_schema(blueprint_id),
         {:ok, defaults} <- SampleBlueprint.default_additional_params(blueprint_id) do
      allowed_keys = Enum.map(schema, & &1.name)

      merged_additional =
        defaults
        |> normalize_map_string_keys()
        |> Map.merge(normalized_additional)
        |> Map.take(allowed_keys)

      %{"blueprint_id" => blueprint_id, "additional" => merged_additional}
    else
      _ ->
        default_machine_settings()
    end
  end

  defp normalize_machine_settings(_blueprint_id, _additional), do: default_machine_settings()

  defp machine_settings_schema(settings) do
    blueprint_id = Map.get(settings, "blueprint_id", SampleBlueprint.default_blueprint_id())

    case SampleBlueprint.additional_param_schema(blueprint_id) do
      {:ok, schema} -> schema
      {:error, _reason} -> []
    end
  end

  defp assign_machine_settings(socket, machine_config) when is_map(machine_config) do
    blueprint_id =
      Map.get(machine_config, :blueprint_id) || Map.get(machine_config, "blueprint_id") ||
        SampleBlueprint.default_blueprint_id()

    additional =
      Map.get(machine_config, :additional_params) || Map.get(machine_config, "additional_params") ||
        %{}

    settings = normalize_machine_settings(blueprint_id, additional)

    socket
    |> assign(:machine_settings, settings)
    |> assign(:machine_schema, machine_settings_schema(settings))
  end

  defp assign_machine_settings(socket, _machine_config) do
    settings = default_machine_settings()

    socket
    |> assign(:machine_settings, settings)
    |> assign(:machine_schema, machine_settings_schema(settings))
  end

  defp normalize_map_string_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      Map.put(acc, normalized_key, value)
    end)
  end

  defp ensure_selected_pad_in_bounds(nil, _row, _column), do: {:error, :invalid_record}

  defp ensure_selected_pad_in_bounds(record, row, column) do
    if row < record.chord_matrix.number_rows and column < record.chord_matrix.number_columns do
      :ok
    else
      {:error, :out_of_bounds}
    end
  end

  defp ensure_row_in_bounds(nil, _row), do: {:error, :invalid_record}

  defp ensure_row_in_bounds(record, row) do
    if row < record.chord_matrix.number_rows, do: :ok, else: {:error, :out_of_bounds}
  end

  defp ensure_column_in_bounds(nil, _column), do: {:error, :invalid_record}

  defp ensure_column_in_bounds(record, column) do
    if column < record.chord_matrix.number_columns, do: :ok, else: {:error, :out_of_bounds}
  end

  defp ensure_progression_loaded(socket, id) do
    case Map.fetch(socket.assigns.progression_records, id) do
      {:ok, _record} ->
        {:ok, socket}

      :error ->
        case ChordProgressions.fetch_progression(id) do
          {:ok, progression_record} ->
            {:ok,
             assign(
               socket,
               :progression_records,
               Map.put(socket.assigns.progression_records, id, progression_record)
             )}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_progression_for_assignment(socket, progression_id) do
    case Map.fetch(socket.assigns.progression_records, progression_id) do
      {:ok, progression_record} ->
        {:ok, progression_record.progression}

      :error ->
        case ChordProgressions.fetch_progression(progression_id) do
          {:ok, progression_record} -> {:ok, progression_record.progression}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp pad_assignment(record, row, col) do
    ChordMatrix.assignment_at(record.chord_matrix, row, col)
  end

  defp pad_cell_classes(selected?, assigned?) do
    [
      "relative aspect-square w-full overflow-hidden rounded-sm border px-1.5 py-1 text-left outline-none",
      "transition-[background-color,border-color,color,box-shadow,transform] duration-200 ease-out",
      "focus-visible:ring-2 focus-visible:ring-offset-0 focus-visible:[--tw-ring-color:var(--cm-pad-focus-ring)]",
      if(assigned?,
        do:
          "[border-color:var(--cm-pad-assigned-border)] [background-color:var(--cm-pad-assigned-bg)] [color:var(--cm-pad-assigned-text)] hover:[border-color:var(--cm-pad-assigned-border-hover)] hover:[background-color:var(--cm-pad-assigned-bg-hover)] [box-shadow:var(--cm-pad-assigned-shadow)]",
        else:
          "[border-color:var(--cm-pad-unassigned-border)] [background-color:var(--cm-pad-unassigned-bg)] [color:var(--cm-pad-unassigned-text)] hover:[border-color:var(--cm-pad-unassigned-border-hover)] hover:[background-color:var(--cm-pad-unassigned-bg-hover)] [box-shadow:var(--cm-pad-unassigned-shadow)]"
      ),
      if(selected?,
        do:
          if(assigned?,
            do:
              "border-2 [border-color:var(--cm-pad-assigned-active-border)] [background-color:var(--cm-pad-assigned-active-bg)] [color:var(--cm-pad-assigned-active-text)] [box-shadow:var(--cm-pad-assigned-active-shadow)]",
            else:
              "border-2 [border-color:var(--cm-pad-unassigned-active-border)] [background-color:var(--cm-pad-unassigned-active-bg)] [color:var(--cm-pad-unassigned-active-text)] [box-shadow:var(--cm-pad-unassigned-active-shadow)]"
          ),
        else: ""
      )
    ]
  end

  defp row_header_classes(selected?) do
    [
      "flex h-full w-full items-center justify-center rounded-sm border font-mono text-[10px] transition-colors duration-150",
      if(selected?,
        do: "border-sky-300/90 bg-sky-500/25 text-sky-100",
        else: "border-zinc-700/80 bg-zinc-900/70 text-zinc-400 hover:border-zinc-500"
      )
    ]
  end

  defp column_header_classes(selected?) do
    [
      "h-8 rounded-sm border font-mono text-[10px] transition-colors duration-150",
      if(selected?,
        do: "border-sky-300/90 bg-sky-500/25 text-sky-100",
        else: "border-zinc-700/80 bg-zinc-900/70 text-zinc-400 hover:border-zinc-500"
      )
    ]
  end

  defp adjust_selection_after_insert(socket, operation, index, record) do
    {new_selected_row, new_selected_column} =
      case operation do
        :row_before ->
          {
            shift_selected_index(socket.assigns.selected_row, index, :before),
            socket.assigns.selected_column
          }

        :row_after ->
          {
            shift_selected_index(socket.assigns.selected_row, index + 1, :before),
            socket.assigns.selected_column
          }

        :column_left ->
          {
            socket.assigns.selected_row,
            shift_selected_index(socket.assigns.selected_column, index, :before)
          }

        :column_right ->
          {
            socket.assigns.selected_row,
            shift_selected_index(socket.assigns.selected_column, index + 1, :before)
          }
      end

    socket
    |> assign(:selected_row, clamp_index(new_selected_row, record.chord_matrix.number_rows))
    |> assign(
      :selected_column,
      clamp_index(new_selected_column, record.chord_matrix.number_columns)
    )
    |> assign(
      :selected_pad,
      shift_selected_pad(socket.assigns.selected_pad, operation, index, record)
    )
  end

  defp adjust_selection_after_remove(socket, axis, removed_index, record) do
    new_selected_row =
      case axis do
        :row -> clamp_index(socket.assigns.selected_row, record.chord_matrix.number_rows)
        :column -> clamp_index(socket.assigns.selected_row, record.chord_matrix.number_rows)
      end

    new_selected_column =
      case axis do
        :row -> clamp_index(socket.assigns.selected_column, record.chord_matrix.number_columns)
        :column -> clamp_index(socket.assigns.selected_column, record.chord_matrix.number_columns)
      end

    socket
    |> assign(:selected_row, new_selected_row)
    |> assign(:selected_column, new_selected_column)
    |> assign(
      :selected_pad,
      shift_selected_pad_on_remove(socket.assigns.selected_pad, axis, removed_index, record)
    )
  end

  defp shift_selected_index(nil, _insertion_index, _mode), do: nil

  defp shift_selected_index(index, insertion_index, :before) when is_integer(index) do
    if index >= insertion_index, do: index + 1, else: index
  end

  defp clamp_index(nil, _max), do: nil
  defp clamp_index(_index, max) when max <= 0, do: nil

  defp clamp_index(index, max) when is_integer(index) do
    index
    |> max(0)
    |> min(max - 1)
  end

  defp shift_selected_pad(nil, _operation, _index, _record), do: nil

  defp shift_selected_pad({row, column}, operation, index, record) do
    shifted =
      case operation do
        :row_before -> if(row >= index, do: {row + 1, column}, else: {row, column})
        :row_after -> if(row > index, do: {row + 1, column}, else: {row, column})
        :column_left -> if(column >= index, do: {row, column + 1}, else: {row, column})
        :column_right -> if(column > index, do: {row, column + 1}, else: {row, column})
      end

    clamp_pad(shifted, record)
  end

  defp shift_selected_pad_on_remove(nil, _axis, _removed_index, _record), do: nil

  defp shift_selected_pad_on_remove({row, column}, :row, removed_index, record) do
    shifted =
      cond do
        row == removed_index -> {min(removed_index, record.chord_matrix.number_rows - 1), column}
        row > removed_index -> {row - 1, column}
        true -> {row, column}
      end

    clamp_pad(shifted, record)
  end

  defp shift_selected_pad_on_remove({row, column}, :column, removed_index, record) do
    shifted =
      cond do
        column == removed_index ->
          {row, min(removed_index, record.chord_matrix.number_columns - 1)}

        column > removed_index ->
          {row, column - 1}

        true ->
          {row, column}
      end

    clamp_pad(shifted, record)
  end

  defp clamp_pad({row, column}, %{chord_matrix: chord_matrix}) do
    cond do
      chord_matrix.number_rows <= 0 or chord_matrix.number_columns <= 0 -> nil
      row < 0 or column < 0 -> nil
      row >= chord_matrix.number_rows or column >= chord_matrix.number_columns -> nil
      true -> {row, column}
    end
  end

  defp count_assignments_in_row(record, row_index) do
    record.chord_matrix.assignments
    |> Map.keys()
    |> Enum.count(fn {row, _column} -> row == row_index end)
  end

  defp count_assignments_in_column(record, column_index) do
    record.chord_matrix.assignments
    |> Map.keys()
    |> Enum.count(fn {_row, column} -> column == column_index end)
  end

  defp play_notes_for_3s(socket, notes, source_label) do
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
               |> assign(:keyboard_active_notes, Enum.uniq(final_notes))
               |> assign(:keyboard_source, source_label)
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
    |> assign_keyboard_from_selected_pad()
  end

  defp assign_keyboard_from_selected_pad(socket) do
    case socket.assigns do
      %{record: %{chord_matrix: %ChordMatrix{} = chord_matrix}, selected_pad: {row, col}} ->
        case ChordMatrix.assignment_at(chord_matrix, row, col) do
          %{chord_spec: %ChordSpec{} = chord_spec} ->
            socket
            |> assign(:keyboard_active_notes, Resolver.resolve(chord_spec))
            |> assign(:keyboard_source, "Selected pad: #{ChordSpec.symbol_label(chord_spec)}")

          _ ->
            socket
            |> assign(:keyboard_active_notes, [])
            |> assign(:keyboard_source, "Selected pad is empty")
        end

      _ ->
        socket
        |> assign(:keyboard_active_notes, [])
        |> assign(:keyboard_source, "No chord selected")
    end
  end

  defp piano_keys(active_notes) when is_list(active_notes) do
    FullPianoKeyboard.key_maps(active_notes: active_notes)
  end

  defp piano_keys(_active_notes), do: []

  defp format_timestamp(value) when is_binary(value) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(value) do
      Calendar.strftime(datetime, "%b %-d, %Y %-I:%M:%S %p UTC")
    else
      _ -> value
    end
  end

  defp format_timestamp(value), do: to_string(value)
end
