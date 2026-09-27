defmodule Mensch.SampleDb do
  @moduledoc """
  Pseudo-database of built-in sample definitions.

  This module stores sample context, timeline defaults, and sample entry
  collections as in-memory Elixir data structures for local development
  and UI selection.
  """

  alias Mensch.SampleContext
  alias Mensch.SampleDb.Sample10DynamicVoicingBFlatIIiivv
  alias Mensch.SampleDb.Sample11DynamicVoicingEMajorIIiivv
  alias Mensch.SampleDb.Sample12RootNote
  alias Mensch.SampleDb.Sample7DynamicVoicing
  alias Mensch.SampleDb.Sample8DynamicVoicingOneBar
  alias Mensch.SampleDb.Sample9DynamicVoicingCMajor

  @default_frame_mbeats 50

  @samples [
    Sample7DynamicVoicing.sample(@default_frame_mbeats),
    Sample9DynamicVoicingCMajor.sample(@default_frame_mbeats),
    Sample8DynamicVoicingOneBar.sample(@default_frame_mbeats),
    Sample10DynamicVoicingBFlatIIiivv.sample(@default_frame_mbeats),
    Sample11DynamicVoicingEMajorIIiivv.sample(@default_frame_mbeats),
    Sample12RootNote.sample(@default_frame_mbeats)
  ]

  @doc "Returns default context used by sample-1 and ad hoc single-chord rendering."
  @spec default_sample_context() :: SampleContext.t()
  def default_sample_context do
    @samples
    |> Enum.at(0, %{})
    |> Map.fetch!(:sample_context)
  end

  @doc "Returns sample-1 entries."
  @spec default_sample_entries() :: [map()]
  def default_sample_entries do
    @samples
    |> Enum.at(0, %{})
    |> Map.fetch!(:sample_entries)
  end

  @doc "Returns all built-in samples for selection in the UI."
  @spec default_samples() :: [map()]
  def default_samples, do: @samples
end
