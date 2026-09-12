defmodule Mensch.SampleDb do
  @moduledoc """
  Pseudo-database of built-in sample definitions.

  This module stores sample context, timeline defaults, and sample entry
  collections as in-memory Elixir data structures for local development
  and UI selection.
  """

  alias Mensch.SampleContext
  alias Mensch.SampleDb.Sample0SimpleChordTraversal
  alias Mensch.SampleDb.Sample0bSimpleChordTraversalUp
  alias Mensch.SampleDb.Sample1
  alias Mensch.SampleDb.Sample1NoRelease
  alias Mensch.SampleDb.Sample2
  alias Mensch.SampleDb.Sample2CMajorChords
  alias Mensch.SampleDb.Sample3
  alias Mensch.SampleDb.Sample4
  alias Mensch.SampleDb.Sample5SimpleChord

  @default_frame_mbeats 50

  @samples [
    Sample0SimpleChordTraversal.sample(@default_frame_mbeats),
    Sample0bSimpleChordTraversalUp.sample(@default_frame_mbeats),
    Sample5SimpleChord.sample(@default_frame_mbeats),
    Sample1.sample(@default_frame_mbeats),
    Sample1NoRelease.sample(@default_frame_mbeats),
    Sample2CMajorChords.sample(@default_frame_mbeats),
    Sample2.sample(@default_frame_mbeats),
    Sample3.sample(@default_frame_mbeats),
    Sample4.sample(@default_frame_mbeats)
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
