defmodule Mensch.ChordPlayer do
  @moduledoc """
  Plays one `%Mensch.Chord{}` live over MIDI.

  Starts one `Mensch.NotePlayer` child per chord tone, each on its own
  MPE member channel with a distinct vibrato phase so their modulation
  is audibly independent (see `Mensch.Midi.Connection`). On stop,
  tells every child note to stop (sending note-off for each) before
  terminating itself, so a chord can never leave notes stuck sounding
  on the hardware.

  Takes a `:chord` (`%Mensch.Chord{}`), an optional `:timing`
  (`%Mensch.Timing{}` snapshot of the global tempo/clock - defaults to
  `Mensch.Timing.now/0` if omitted), and an optional `:duration_bars`
  (musical time, not raw milliseconds). If `:duration_bars` is
  positive, the player automatically stops itself once that many bars
  have elapsed (per `:timing`'s bpm). A `:duration_bars` of `0` (the
  default) means the chord holds indefinitely, until `stop/1` is
  called.
  """

  use GenServer

  alias Mensch.Chord
  alias Mensch.Harmony.Key
  alias Mensch.Midi.Connection
  alias Mensch.NotePlayer
  alias Mensch.Timing

  defstruct [:chord, :timing, duration_bars: 0, notes: []]

  @default_velocity 100

  # Client API

  @doc """
  Starts playing a chord. `opts` must include `:chord`
  (`%Mensch.Chord{}`). Optionally takes `:timing` (`%Mensch.Timing{}`,
  defaults to `Mensch.Timing.now/0`) and `:duration_bars` (number,
  default `0` = hold indefinitely).
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

  @doc """
  Returns how far along (0.0..1.0) this chord is through its own
  `:duration_bars`, based on the global tempo/clock captured in
  `:timing` - or `nil` when `:duration_bars` is `0` (holds
  indefinitely, so it has no total duration to measure against).
  """
  def progress(pid) do
    GenServer.call(pid, :progress)
  catch
    :exit, _ -> nil
  end

  # Server callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    chord = Keyword.fetch!(opts, :chord)
    timing = Keyword.get(opts, :timing, Timing.now())
    duration_bars = Keyword.get(opts, :duration_bars, 0)

    channels = Connection.member_channels()
    tones = Chord.notes(chord)
    note_count = length(tones)

    notes =
      tones
      |> Enum.zip(Enum.take(channels, note_count))
      |> Enum.with_index()
      |> Enum.map(fn {{note, channel}, index} ->
        {:ok, pid} =
          NotePlayer.start_link(
            number: midi_note_number(note, chord.octave),
            channel: channel,
            velocity: @default_velocity,
            phase: index / max(note_count, 1) * 2 * :math.pi(),
            emphasis: index == 0
          )

        pid
      end)

    if duration_bars > 0 do
      Process.send_after(self(), :duration_elapsed, Timing.bars_to_ms(timing, duration_bars))
    end

    state = %__MODULE__{
      chord: chord,
      timing: timing,
      duration_bars: duration_bars,
      notes: notes
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  def handle_info(:duration_elapsed, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    notes_info =
      state.chord
      |> Chord.notes()
      |> Enum.zip(state.notes)
      |> Enum.map(fn {note, pid} ->
        case NotePlayer.snapshot(pid) do
          nil -> nil
          info -> Map.merge(info, %{note: note, octave: state.chord.octave})
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, notes_info, state}
  end

  def handle_call(:progress, _from, %{duration_bars: duration_bars} = state)
      when duration_bars <= 0 do
    {:reply, nil, state}
  end

  def handle_call(:progress, _from, state) do
    total_ms = Timing.bars_to_ms(state.timing, state.duration_bars)
    percent = Timing.elapsed_ms(state.timing) / total_ms
    {:reply, percent |> max(0.0) |> min(1.0), state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.notes, fn pid ->
      if Process.alive?(pid), do: NotePlayer.stop(pid)
    end)

    :ok
  end

  defp midi_note_number(note, octave) do
    semitone = Enum.find_index(Key.notes(), &(&1 == note))
    (octave + 1) * 12 + semitone
  end
end
