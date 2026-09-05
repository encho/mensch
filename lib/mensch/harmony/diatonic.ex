defmodule Mensch.Harmony.Diatonic do
  @moduledoc """
  Diatonic correctness checks: which chord modifiers can be built
  entirely from the notes already present in a scale's mode, for a
  given scale degree, with no chromatic alteration.
  """

  alias Mensch.Harmony.{Resolver, Scale}

  @doc """
  Returns the subset of `Mensch.Harmony.Resolver.modifiers/0` that are
  diatonically correct for `degree` within `mode` - i.e. every chord
  tone they produce is already a note of that scale.
  """
  @spec valid_modifiers(Scale.mode(), atom()) :: [atom()]
  def valid_modifiers(mode, degree) do
    offsets = diatonic_offsets(mode, degree)

    Enum.filter(Resolver.modifiers(), fn modifier ->
      modifier |> Resolver.chord_tones() |> Enum.all?(&(Integer.mod(&1, 12) in offsets))
    end)
  end

  defp diatonic_offsets(mode, degree) do
    steps = Scale.scale_steps(mode)
    root_index = Scale.degree_number(degree) - 1
    root_step = Enum.at(steps, root_index)

    for step <- 0..6, into: MapSet.new() do
      target_step = Enum.at(steps, rem(root_index + step, 7))
      Integer.mod(target_step - root_step, 12)
    end
  end
end
