defmodule Mensch.Harmony.Key do
  @moduledoc """
  A musical key: a root note plus a scale.

  Only the major scale is implemented for now, but the struct shape
  leaves room for other scales later.
  """

  defstruct root: :c, scale: :major

  @type note ::
          :c
          | :c_sharp
          | :d
          | :d_sharp
          | :e
          | :f
          | :f_sharp
          | :g
          | :g_sharp
          | :a
          | :a_sharp
          | :b

  @type t :: %__MODULE__{root: note(), scale: :major}

  @notes ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a

  @major_scale_steps [0, 2, 4, 5, 7, 9, 11]

  @degree_numbers %{
    i: 1,
    I: 1,
    ii: 2,
    II: 2,
    iii: 3,
    III: 3,
    iv: 4,
    IV: 4,
    v: 5,
    V: 5,
    vi: 6,
    VI: 6,
    vii: 7,
    VII: 7
  }

  @doc "Returns the twelve note names, in pitch-class order starting at C."
  @spec notes() :: [note()]
  def notes, do: @notes

  @doc "Returns `note` transposed by `semitones` (wrapping within the octave)."
  @spec transpose(note(), integer()) :: note()
  def transpose(note, semitones) when is_atom(note) and is_integer(semitones) do
    index = Enum.find_index(@notes, &(&1 == note))
    Enum.at(@notes, Integer.mod(index + semitones, 12))
  end

  @doc """
  Returns the note at the given roman-numeral scale degree (e.g. `:ii`,
  `:V`) within this key.
  """
  @spec note_at_degree(t(), atom()) :: note()
  def note_at_degree(%__MODULE__{root: root, scale: :major}, degree) do
    steps = Map.fetch!(@degree_numbers, degree) |> then(&Enum.at(@major_scale_steps, &1 - 1))
    transpose(root, steps)
  end
end
