defmodule Mensch.ChordMatrixPadPlayer do
  @moduledoc """
  Builds and plays expressive single-pad performances from a chord matrix.

  Performances are cached in-memory by matrix record revision + pad coordinate
  so repeated pad clicks do not rebuild MIDI frame timelines.
  """

  alias Mensch.Harmony.ChordMatrix
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Performance
  alias Mensch.PerformanceAssembler
  alias Mensch.Player
  alias Mensch.SampleBlueprint

  @cache_table :mensch_chord_matrix_pad_performance_cache
  @cache_limit 512

  @spec play_pad(map(), integer(), integer()) :: :ok | {:error, term()}
  def play_pad(record, row, column)
      when is_map(record) and is_integer(row) and row >= 0 and is_integer(column) and column >= 0 do
    with {:ok, performance} <- performance_for_pad(record, row, column) do
      play_performance(performance)
    end
  end

  def play_pad(_record, _row, _column), do: {:error, :invalid_pad}

  @spec play_performance(Performance.t()) :: :ok | {:error, term()}
  def play_performance(%Performance{} = performance) do
    with :ok <- ensure_midi_connected() do
      Player.play(performance)
    end
  end

  def play_performance(_performance), do: {:error, :invalid_performance}

  @spec performance_for_pad(map(), integer(), integer()) ::
          {:ok, Performance.t()} | {:error, term()}
  def performance_for_pad(record, row, column)
      when is_map(record) and is_integer(row) and row >= 0 and is_integer(column) and column >= 0 do
    with {:ok, chord_matrix} <- fetch_chord_matrix(record),
         {:ok, chord_spec} <- fetch_pad_chord(chord_matrix, row, column) do
      key = cache_key(record, row, column)

      case cache_get(key) do
        {:ok, %Performance{} = performance} ->
          {:ok, performance}

        :miss ->
          with {:ok, performance} <- build_pad_performance(chord_matrix, chord_spec) do
            cache_put(key, performance)
            {:ok, performance}
          end
      end
    end
  end

  def performance_for_pad(_record, _row, _column), do: {:error, :invalid_pad}

  @spec clear_cache() :: :ok
  def clear_cache do
    table = ensure_cache_table()
    :ets.delete_all_objects(table)
    :ok
  end

  defp fetch_chord_matrix(record) do
    case Map.get(record, :chord_matrix) do
      %ChordMatrix{} = chord_matrix -> {:ok, chord_matrix}
      _ -> {:error, :invalid_record}
    end
  end

  defp fetch_pad_chord(%ChordMatrix{} = chord_matrix, row, column) do
    case ChordMatrix.assignment_at(chord_matrix, row, column) do
      %{chord_spec: %ChordSpec{} = chord_spec} -> {:ok, chord_spec}
      _ -> {:error, :pad_unassigned}
    end
  end

  defp ensure_midi_connected do
    case Mensch.Midi.Connection.status() do
      {:connected, _port_name} -> :ok
      :disconnected -> {:error, :disconnected}
    end
  end

  defp build_pad_performance(%ChordMatrix{} = chord_matrix, %ChordSpec{} = chord_spec) do
    build_opts = %{
      name: "Chord Matrix Pad Preview",
      blueprint_id: machine_blueprint_id(chord_matrix),
      bpm: chord_matrix.bpm,
      time_signature: chord_matrix.time_signature,
      frame_mbeats: chord_matrix.frame_mbeats,
      chord_duration_mbeats: chord_matrix.duration_mbeats,
      silence_after_chord_mbeats: 0,
      blueprint_additional_params: machine_additional_params(chord_matrix),
      chords: [chord_spec]
    }

    with {:ok, sample} <- SampleBlueprint.build(build_opts) do
      performance =
        PerformanceAssembler.generate_sample(sample.sample_entries, sample.sample_context,
          total_length_mbeats: sample.total_length_mbeats
        )

      {:ok, performance}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [ArgumentError, RuntimeError] -> {:error, Exception.message(error)}
  end

  defp machine_blueprint_id(%ChordMatrix{machine: machine}) when is_map(machine) do
    Map.get(machine, :blueprint_id) || Map.get(machine, "blueprint_id") ||
      SampleBlueprint.default_blueprint_id()
  end

  defp machine_blueprint_id(_chord_matrix), do: SampleBlueprint.default_blueprint_id()

  defp machine_additional_params(%ChordMatrix{machine: machine}) when is_map(machine) do
    value = Map.get(machine, :additional_params) || Map.get(machine, "additional_params") || %{}

    if is_map(value), do: value, else: %{}
  end

  defp machine_additional_params(_chord_matrix), do: %{}

  defp cache_key(record, row, column) do
    id = Map.get(record, :id)
    updated_at = Map.get(record, :updated_at)
    {id, updated_at, row, column}
  end

  defp cache_get(key) do
    table = ensure_cache_table()

    case :ets.lookup(table, key) do
      [{^key, %Performance{} = performance}] -> {:ok, performance}
      _ -> :miss
    end
  end

  defp cache_put(key, %Performance{} = performance) do
    table = ensure_cache_table()
    :ets.insert(table, {key, performance})

    if :ets.info(table, :size) > @cache_limit do
      :ets.delete_all_objects(table)
    end

    :ok
  end

  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @cache_table
        end

      _tid ->
        @cache_table
    end
  end
end
