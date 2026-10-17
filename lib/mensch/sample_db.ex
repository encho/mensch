defmodule Mensch.SampleDb do
  @moduledoc """
  Pseudo-database of built-in sample definitions.

  This module stores sample context, timeline defaults, and sample entry
  collections as in-memory Elixir data structures for local development
  and UI selection.
  """

  alias Mensch.SampleContext
  alias Mensch.SampleDefinition
  alias Mensch.SampleEntry
  alias Mensch.TimelineContext
  alias Mensch.SampleDb.Sample10DynamicVoicingBFlatIIiivv
  alias Mensch.SampleDb.Sample11DynamicVoicingEMajorIIiivv
  alias Mensch.SampleDb.Sample12RootNote
  alias Mensch.SampleDb.Sample13Strum
  alias Mensch.SampleDb.Sample14StrumCMajorSixteenChords
  alias Mensch.SampleDb.Sample15StrumCMajorIViIiVProgression
  alias Mensch.SampleDb.Sample7DynamicVoicing
  alias Mensch.SampleDb.Sample8DynamicVoicingOneBar
  alias Mensch.SampleDb.Sample9DynamicVoicingCMajor

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample15

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample16

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample22

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample23

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample35

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample43

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample3

  alias Mensch.SampleDb.GeneratedChordListGeneratedSample7

  @default_frame_mbeats 50
  @legacy_created_at ~U[2026-01-01 00:00:00Z]

  @samples [
    Sample7DynamicVoicing.sample(@default_frame_mbeats),
    Sample9DynamicVoicingCMajor.sample(@default_frame_mbeats),
    Sample8DynamicVoicingOneBar.sample(@default_frame_mbeats),
    Sample10DynamicVoicingBFlatIIiivv.sample(@default_frame_mbeats),
    Sample11DynamicVoicingEMajorIIiivv.sample(@default_frame_mbeats),
    Sample12RootNote.sample(@default_frame_mbeats),
    Sample13Strum.sample(@default_frame_mbeats),
    Sample14StrumCMajorSixteenChords.sample(@default_frame_mbeats),
    Sample15StrumCMajorIViIiVProgression.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample15.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample16.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample22.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample23.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample35.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample43.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample3.sample(@default_frame_mbeats),
    GeneratedChordListGeneratedSample7.sample(@default_frame_mbeats)
  ]

  @doc "Returns sample total length in mbeats, honoring optional `:total_length_bars` or `:total_length_mbeats`."
  @spec sample_total_length_mbeats(SampleDefinition.t()) :: non_neg_integer()
  def sample_total_length_mbeats(
        %SampleDefinition{
          sample_entries: entries,
          sample_context: %SampleContext{} = sample_context
        } =
          sample
      )
      when is_list(entries) do
    natural_end_mbeat = natural_sample_end_mbeat(entries, sample_context)

    configured_total_mbeats =
      case Map.get(sample, :total_length_mbeats) do
        value when is_integer(value) and value >= 0 -> value
        _ -> configured_total_mbeats_from_bars(sample, sample_context)
      end

    max(natural_end_mbeat, configured_total_mbeats)
  end

  def sample_total_length_mbeats(_sample), do: 0

  defp with_normalized_total_length(%SampleDefinition{} = sample) do
    sample =
      if is_nil(Map.get(sample, :created_at)) do
        Map.put(sample, :created_at, @legacy_created_at)
      else
        sample
      end

    %SampleDefinition{sample | total_length_mbeats: sample_total_length_mbeats(sample)}
  end

  defp with_normalized_total_length(sample), do: sample

  defp configured_total_mbeats_from_bars(
         %SampleDefinition{} = sample,
         %SampleContext{} = sample_context
       ) do
    case sample.total_length_bars do
      value when is_integer(value) and value >= 0 ->
        value * SampleContext.mbeats_per_bar(sample_context)

      _ ->
        0
    end
  end

  defp natural_sample_end_mbeat(entries, %SampleContext{} = sample_context) do
    entries
    |> Enum.map(fn %SampleEntry{timeline_context: timeline_context} ->
      TimelineContext.end_mbeat(timeline_context, sample_context)
    end)
    |> Enum.max(fn -> 0 end)
  end

  @doc "Returns default context used by sample-1 and ad hoc single-chord rendering."
  @spec default_sample_context() :: SampleContext.t()
  def default_sample_context do
    default_samples()
    |> Enum.at(0, %{})
    |> Map.fetch!(:sample_context)
  end

  @doc "Returns sample-1 entries."
  @spec default_sample_entries() :: [SampleEntry.t()]
  def default_sample_entries do
    default_samples()
    |> Enum.at(0, %{})
    |> Map.fetch!(:sample_entries)
  end

  @doc "Returns all built-in samples for selection in the UI."
  @spec default_samples() :: [SampleDefinition.t()]
  def default_samples do
    Enum.map(@samples, &with_normalized_total_length/1)
  end
end
