defmodule MenschWeb.ExportController do
  use MenschWeb, :controller

  alias Mensch.MidiFile
  alias Mensch.PerformanceAssembler
  alias Mensch.SampleDb
  alias Mensch.TimelineContext

  def mpe_midi(conn, %{"index" => index_str}) do
    with {index, ""} <- Integer.parse(index_str),
         {:ok, sample} <- sample_by_index(index) do
      performance =
        PerformanceAssembler.generate_sample(sample.sample_entries, sample.sample_context)

      midi_bytes =
        MidiFile.from_performance(performance, sample.sample_context,
          trim_end_tick: sample_end_mbeat(sample)
        )

      filename = "#{sample_slug(sample.name)}-mpe.mid"

      send_download(conn, {:binary, midi_bytes}, filename: filename, content_type: "audio/midi")
    else
      _ -> send_resp(conn, 404, "sample not found")
    end
  end

  def mpe_report(conn, %{"index" => index_str}) do
    with {index, ""} <- Integer.parse(index_str),
         {:ok, sample} <- sample_by_index(index) do
      performance =
        PerformanceAssembler.generate_sample(sample.sample_entries, sample.sample_context)

      report = MidiFile.mpe_report(performance)
      filename = "#{sample_slug(sample.name)}-mpe-events.txt"

      send_download(conn, {:binary, report}, filename: filename, content_type: "text/plain")
    else
      _ -> send_resp(conn, 404, "sample not found")
    end
  end

  def bitwig_mpe_midi(conn, %{"index" => index_str}) do
    with {index, ""} <- Integer.parse(index_str),
         {:ok, sample} <- sample_by_index(index) do
      performance =
        PerformanceAssembler.generate_sample(sample.sample_entries, sample.sample_context)

      midi_bytes =
        MidiFile.from_performance_bitwig(performance, sample.sample_context,
          trim_end_tick: sample_end_mbeat(sample)
        )

      filename = "#{sample_slug(sample.name)}-bitwig-mpe.mid"

      send_download(conn, {:binary, midi_bytes}, filename: filename, content_type: "audio/midi")
    else
      _ -> send_resp(conn, 404, "sample not found")
    end
  end

  defp sample_by_index(index) when is_integer(index) and index >= 0 do
    case Enum.at(SampleDb.default_samples(), index) do
      %{sample_entries: _entries, sample_context: _context, name: _name} = sample -> {:ok, sample}
      _ -> :error
    end
  end

  defp sample_by_index(_index), do: :error

  defp sample_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp sample_end_mbeat(%{sample_entries: entries, sample_context: sample_context})
       when is_list(entries) do
    entries
    |> Enum.map(fn %{timeline_context: timeline_context} ->
      TimelineContext.end_mbeat(timeline_context, sample_context)
    end)
    |> Enum.max(fn -> 0 end)
  end
end
