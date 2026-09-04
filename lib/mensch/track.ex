defmodule Mensch.Track do
  @moduledoc """
  A track holds 16 trigs, a Harmonic Context (scale/root or chromatic),
  and a Machine (currently always `Mensch.Machine.SingleNote`) that
  define their default musical parameters.
  """

  alias Mensch.HarmonicContext
  alias Mensch.Machine.SingleNote
  alias Mensch.ParameterResolver
  alias Mensch.Trig

  defstruct [:id, :name, harmonic_context: nil, machine: nil, trigs: []]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          harmonic_context: HarmonicContext.t(),
          machine: SingleNote.t(),
          trigs: [Trig.t()]
        }

  @trig_count 16

  @doc "Builds a track with #{@trig_count} empty trigs, a default Harmonic Context, and a default SINGLE_NOTE machine."
  @spec new(pos_integer(), String.t()) :: t()
  def new(id, name) do
    trigs = for step <- 1..@trig_count, do: Trig.new(step)

    %__MODULE__{
      id: id,
      name: name,
      harmonic_context: HarmonicContext.new(),
      machine: SingleNote.new(),
      trigs: trigs
    }
  end

  @doc "Returns the trig at the given step, or nil if not found."
  @spec trig_at(t(), pos_integer()) :: Trig.t() | nil
  def trig_at(%__MODULE__{trigs: trigs}, step) do
    Enum.find(trigs, &(&1.step == step))
  end

  @doc "Applies a Program Mode tap at `step` using the given selected trig type."
  @spec apply_program_tap(t(), pos_integer(), Trig.trig_type()) :: t()
  def apply_program_tap(%__MODULE__{} = track, step, selected_type) do
    update_trig(track, step, &Trig.apply_program_tap(&1, selected_type))
  end

  @doc "Locks `key` within `namespace` on the trig at `step`, starting from the current Track default."
  @spec lock_param(t(), pos_integer(), Trig.lock_namespace(), atom()) :: t()
  def lock_param(%__MODULE__{} = track, step, namespace, key) do
    default_val = track |> default_value(namespace) |> Map.fetch!(key)
    update_trig(track, step, &Trig.lock(&1, namespace, key, default_val))
  end

  @doc "Clears the lock for `key` within `namespace` on the trig at `step`."
  @spec clear_lock(t(), pos_integer(), Trig.lock_namespace(), atom()) :: t()
  def clear_lock(%__MODULE__{} = track, step, namespace, key) do
    update_trig(track, step, &Trig.clear_lock(&1, namespace, key))
  end

  @doc "Nudges the locked value for `key` within `namespace` on the trig at `step` up or down."
  @spec adjust_lock(t(), pos_integer(), Trig.lock_namespace(), atom(), :up | :down) :: t()
  def adjust_lock(%__MODULE__{} = track, step, namespace, key, direction) do
    update_trig(track, step, &Trig.adjust_lock(&1, namespace, key, direction))
  end

  @doc "Effective Harmonic Context for the trig at `step`: Track default overridden by locks."
  @spec effective_harmonic_context(t(), pos_integer()) :: HarmonicContext.t()
  def effective_harmonic_context(%__MODULE__{harmonic_context: harmonic_context} = track, step) do
    ParameterResolver.resolve(harmonic_context, trig_at(track, step), :harmonic_context)
  end

  @doc "Effective Machine for the trig at `step`: Track default overridden by locks."
  @spec effective_machine(t(), pos_integer()) :: SingleNote.t()
  def effective_machine(%__MODULE__{machine: machine} = track, step) do
    ParameterResolver.resolve(machine, trig_at(track, step), :machine)
  end

  @doc "Resolves the sounding note name for the trig at `step`."
  @spec resolved_note(t(), pos_integer()) :: String.t()
  def resolved_note(%__MODULE__{} = track, step) do
    SingleNote.resolve_note(
      effective_harmonic_context(track, step),
      effective_machine(track, step)
    )
  end

  @doc "Toggles the Track's Harmonic Context between Scale and Chromatic mode."
  @spec toggle_harmonic_mode(t()) :: t()
  def toggle_harmonic_mode(%__MODULE__{harmonic_context: %{mode: :scale}} = track) do
    set_harmonic_mode(track, :chromatic)
  end

  def toggle_harmonic_mode(%__MODULE__{harmonic_context: %{mode: :chromatic}} = track) do
    set_harmonic_mode(track, :scale)
  end

  @doc "Nudges a Track default up or down for `namespace`/`key` (not a Trig lock)."
  @spec adjust_default(t(), Trig.lock_namespace(), atom(), :up | :down) :: t()
  def adjust_default(%__MODULE__{} = track, namespace, key, direction) do
    current = track |> default_value(namespace) |> Map.fetch!(key)
    new_value = ParameterResolver.adjust(namespace, key, current, direction)
    put_default(track, namespace, key, new_value)
  end

  defp set_harmonic_mode(
         %__MODULE__{harmonic_context: harmonic_context, machine: machine} = track,
         mode
       ) do
    default_pitch =
      case mode do
        :scale -> {:degree, 1}
        :chromatic -> {:note, :c}
      end

    %{
      track
      | harmonic_context: %{harmonic_context | mode: mode},
        machine: %{machine | pitch: default_pitch}
    }
    |> sanitize_pitch_locks(mode)
  end

  # A Trig's `:machine, :pitch` lock is only meaningful for the mode it was
  # created under ({:degree, _} for Scale, {:note, _} for Chromatic).
  # Clear any lock left over from before a mode switch so resolution never
  # sees a mismatched pitch shape.
  defp sanitize_pitch_locks(%__MODULE__{trigs: trigs} = track, mode) do
    trigs =
      Enum.map(trigs, fn trig ->
        case get_in(trig.locks, [:machine, :pitch]) do
          {:degree, _} when mode == :chromatic -> Trig.clear_lock(trig, :machine, :pitch)
          {:note, _} when mode == :scale -> Trig.clear_lock(trig, :machine, :pitch)
          _ -> trig
        end
      end)

    %{track | trigs: trigs}
  end

  defp default_value(%__MODULE__{harmonic_context: harmonic_context}, :harmonic_context) do
    Map.from_struct(harmonic_context)
  end

  defp default_value(%__MODULE__{machine: machine}, :machine), do: Map.from_struct(machine)

  defp put_default(
         %__MODULE__{harmonic_context: harmonic_context} = track,
         :harmonic_context,
         key,
         value
       ) do
    %{track | harmonic_context: Map.put(harmonic_context, key, value)}
  end

  defp put_default(%__MODULE__{machine: machine} = track, :machine, key, value) do
    %{track | machine: Map.put(machine, key, value)}
  end

  defp update_trig(%__MODULE__{trigs: trigs} = track, step, fun) do
    trigs =
      Enum.map(trigs, fn
        %Trig{step: ^step} = trig -> fun.(trig)
        trig -> trig
      end)

    %{track | trigs: trigs}
  end
end
