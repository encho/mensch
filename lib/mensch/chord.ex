defmodule Mensch.Chord do
  @moduledoc """
  Represents one currently-playing chord: a key, a scale degree (e.g.
  `:ii`, `:V`) and a quality modifier (e.g. `:min7`, `:maj7`), plus the
  octave to play it in.

  On start, resolves the chord tones against the key/degree/modifier
  and starts one `Mensch.Note` child per chord tone, each on its own
  MPE member channel with a distinct vibrato phase so their modulation
  is audibly independent (see `Mensch.Midi.Connection`). On stop,
  tells every child note to stop (sending note-off for each) before
  terminating itself, so a chord can never leave notes stuck sounding
  on the hardware.
  """

  use GenServer

  alias Mensch.Harmony.{ChordSpec, Key, Resolver}
  alias Mensch.Midi.Connection

  defstruct [:key, :degree, :modifier, :octave, :resolved, notes: []]

  @default_velocity 100

  # Client API

  @doc """
  Starts a chord. `opts` must include `:key` (`%Mensch.Harmony.Key{}`),
  `:degree` and `:modifier` (see `Mensch.Harmony.ChordSpec`), and
  `:octave` (integer; 4 is the octave containing middle C).
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the chord, stopping every note (sending note-off for each)."
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Returns a list of `%{note:, octave:, number:, channel:, pressure:, bend:}`
  maps, one per currently sounding note, in the same order as the
  chord's tones.
  """
  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
  catch
    :exit, _ -> []
  end

  # Server callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    key = Keyword.fetch!(opts, :key)
    degree = Keyword.fetch!(opts, :degree)
    modifier = Keyword.fetch!(opts, :modifier)
    octave = Keyword.fetch!(opts, :octave)

    resolved = Resolver.resolve(key, %ChordSpec{degree: degree, modifier: modifier})
    channels = Connection.member_channels()
    note_count = length(resolved.notes)

    notes =
      resolved.notes
      |> Enum.zip(Enum.take(channels, note_count))
      |> Enum.with_index()
      |> Enum.map(fn {{note, channel}, index} ->
        {:ok, pid} =
          Mensch.Note.start_link(
            number: midi_note_number(note, octave),
            channel: channel,
            velocity: @default_velocity,
            phase: index / max(note_count, 1) * 2 * :math.pi()
          )

        pid
      end)

    state = %__MODULE__{
      key: key,
      degree: degree,
      modifier: modifier,
      octave: octave,
      resolved: resolved,
      notes: notes
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    notes_info =
      state.resolved.notes
      |> Enum.zip(state.notes)
      |> Enum.map(fn {note, pid} ->
        case Mensch.Note.snapshot(pid) do
          nil -> nil
          info -> Map.merge(info, %{note: note, octave: state.octave})
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, notes_info, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.notes, fn pid ->
      if Process.alive?(pid), do: Mensch.Note.stop(pid)
    end)

    :ok
  end

  defp midi_note_number(note, octave) do
    semitone = Enum.find_index(Key.notes(), &(&1 == note))
    (octave + 1) * 12 + semitone
  end
end
