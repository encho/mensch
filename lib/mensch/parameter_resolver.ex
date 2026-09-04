defmodule Mensch.ParameterResolver do
  @moduledoc """
  Resolves effective parameters for a namespace (Harmonic Context or
  Machine) by merging a Track's defaults with a Trig's namespaced
  parameter locks. Locks win; no lock means the value is inherited from
  the Track default.
  """

  alias Mensch.Scale
  alias Mensch.Trig

  @doc """
  Merges `defaults` (a `Mensch.HarmonicContext` or
  `Mensch.Machine.SingleNote` struct) with the trig's locks for
  `namespace`.
  """
  @spec resolve(struct(), Trig.t(), Trig.lock_namespace()) :: struct()
  def resolve(defaults, %Trig{locks: locks}, namespace) do
    struct(defaults, Map.get(locks, namespace, %{}))
  end

  @doc "Nudges a value up or down for `namespace`/`key`, with clamping or cycling as appropriate."
  @spec adjust(Trig.lock_namespace(), atom(), term(), :up | :down) :: term()
  def adjust(:harmonic_context, :root, root, direction) do
    cycle(Scale.note_classes(), root, direction)
  end

  def adjust(:harmonic_context, :scale, scale, _direction) do
    # Only :major is implemented today; no-op until more scales exist.
    scale
  end

  def adjust(:harmonic_context, :mode, :scale, _direction), do: :chromatic
  def adjust(:harmonic_context, :mode, :chromatic, _direction), do: :scale

  def adjust(:machine, :pitch, {:degree, degree}, direction) do
    {:degree, max(degree + step(direction), 1)}
  end

  def adjust(:machine, :pitch, {:note, note_class}, direction) do
    {:note, cycle(Scale.note_classes(), note_class, direction)}
  end

  def adjust(:machine, :octave, octave, direction), do: octave + step(direction)

  def adjust(:machine, :velocity, velocity, direction) do
    velocity |> Kernel.+(step(direction, 5)) |> max(0) |> min(127)
  end

  def adjust(:machine, key, value, direction) when key in [:pressure, :aftertouch] do
    value |> Kernel.+(step(direction, 0.05)) |> max(0.0) |> min(1.0) |> Float.round(2)
  end

  def adjust(:machine, :pitch_offset, value, direction) do
    value |> Kernel.+(step(direction, 0.05)) |> max(-1.0) |> min(1.0) |> Float.round(2)
  end

  def adjust(:machine, key, {:beats, beats}, direction) when key in [:duration, :release] do
    delta = step(direction, 0.25)
    new_beats = max(beats + delta, 0.25)
    {:beats, Float.round(new_beats * 1.0, 2)}
  end

  defp cycle(values, current, direction) do
    count = length(values)
    index = Enum.find_index(values, &(&1 == current))
    Enum.at(values, Integer.mod(index + step(direction), count))
  end

  defp step(:up), do: 1
  defp step(:down), do: -1

  defp step(:up, amount), do: amount
  defp step(:down, amount), do: -amount
end
