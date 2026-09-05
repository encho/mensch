defmodule Mensch.Harmony.Scale do
  @moduledoc """
  A musical scale: a key (root note) plus a mode (major or minor).
  """

  defstruct key: :c, mode: :major

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

  @type mode :: :major | :minor

  @type t :: %__MODULE__{key: note(), mode: mode()}

  @notes ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a

  @major_scale_steps [0, 2, 4, 5, 7, 9, 11]
  @minor_scale_steps [0, 2, 3, 5, 7, 8, 10]

  @roman_numerals ~w(I II III IV V VI VII)

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

  @doc "Returns the scale-step semitone offsets (from the tonic) for `mode`."
  @spec scale_steps(mode()) :: [0..11]
  def scale_steps(:major), do: @major_scale_steps
  def scale_steps(:minor), do: @minor_scale_steps

  @doc "Returns the scale degree number (`1`..`7`) for a roman-numeral `degree` (e.g. `:ii`, `:V`)."
  @spec degree_number(atom()) :: 1..7
  def degree_number(degree), do: Map.fetch!(@degree_numbers, degree)

  @doc """
  Returns the note at the given roman-numeral scale degree (e.g. `:ii`,
  `:V`) within this scale.
  """
  @spec note_at_degree(t(), atom()) :: note()
  def note_at_degree(%__MODULE__{key: key, mode: mode}, degree) do
    step = Enum.at(scale_steps(mode), degree_number(degree) - 1)
    transpose(key, step)
  end

  @doc """
  Returns the correctly-cased roman numeral for `degree` within `mode`
  (uppercase for a major/augmented triad, lowercase for a minor/
  diminished triad), e.g. `roman_numeral(:major, :ii)` is `"ii"`.
  """
  @spec roman_numeral(mode(), atom()) :: String.t()
  def roman_numeral(mode, degree) do
    steps = scale_steps(mode)
    root_index = degree_number(degree) - 1
    root_step = Enum.at(steps, root_index)
    third_step = Enum.at(steps, rem(root_index + 2, 7))
    third_interval = Integer.mod(third_step - root_step, 12)

    base = Enum.at(@roman_numerals, root_index)
    if third_interval == 4, do: base, else: String.downcase(base)
  end
end
