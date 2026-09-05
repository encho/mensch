defmodule Mensch.Midi.Writer do
  @moduledoc """
  Writes a Standard MIDI File (format 0, single track) from a
  performance timeline.

  This is a static file export, unrelated to real-time MIDI playback:
  positions are given in beats (quarter notes) and converted to MIDI
  ticks using a fixed pulses-per-quarter-note resolution.

  `:pressure` events become channel pressure (aftertouch) messages and
  `:pitch_bend` events become pitch wheel messages, both on the same
  channel as the notes — this is a simplification of true MPE (which
  allocates one channel per note); a per-note-channel MPE zone is
  future work.

  Pitch bend is encoded assuming a receiving instrument's default
  (non-MPE) pitch bend wheel range of +/-2 semitones — the standard
  MIDI default most synths use unless explicitly reconfigured — so
  that exported bends are audible without the user having to change
  any settings in their DAW/instrument.
  """

  alias Mensch.Harmony.Key
  alias Mensch.Performance.Event

  @ticks_per_beat 480
  @default_velocity 64
  @pitch_bend_range_semitones 2

  @doc "Encodes `events` at `bpm` into a binary Standard MIDI File (format 0)."
  @spec encode([Event.t()], pos_integer()) :: binary()
  def encode(events, bpm) when is_list(events) and is_integer(bpm) and bpm > 0 do
    header_chunk() <> track_chunk(events, bpm)
  end

  defp header_chunk do
    "MThd" <> <<6::32, 0::16, 1::16, @ticks_per_beat::16>>
  end

  defp track_chunk(events, bpm) do
    body = tempo_event(bpm) <> note_events(events) <> end_of_track_event()
    "MTrk" <> <<byte_size(body)::32>> <> body
  end

  defp tempo_event(bpm) do
    microseconds_per_quarter = div(60_000_000, bpm)
    vlq(0) <> <<0xFF, 0x51, 3, microseconds_per_quarter::24>>
  end

  defp end_of_track_event, do: vlq(0) <> <<0xFF, 0x2F, 0>>

  defp note_events(events) do
    events
    |> Enum.map(&{tick(&1.at_beat), midi_bytes(&1)})
    |> Enum.sort_by(fn {tick, _bytes} -> tick end)
    |> with_deltas()
    |> Enum.map_join(fn {delta, bytes} -> vlq(delta) <> bytes end)
  end

  defp with_deltas(ticked_events) do
    {events, _last_tick} =
      Enum.map_reduce(ticked_events, 0, fn {tick, bytes}, previous_tick ->
        {{tick - previous_tick, bytes}, tick}
      end)

    events
  end

  defp tick(at_beat), do: round(at_beat * @ticks_per_beat)

  defp midi_bytes(%Event{type: :note_on, note: note, velocity: velocity}) do
    <<0x90, midi_note_number(note), velocity || @default_velocity>>
  end

  defp midi_bytes(%Event{type: :note_off, note: note}) do
    <<0x80, midi_note_number(note), 0>>
  end

  defp midi_bytes(%Event{type: :pressure, value: value}) do
    <<0xD0, clamp_7bit(round(value * 127))>>
  end

  defp midi_bytes(%Event{type: :pitch_bend, value: semitones}) do
    bend = pitch_bend_14bit(semitones)
    <<0xE0, rem(bend, 128), div(bend, 128)>>
  end

  defp pitch_bend_14bit(semitones) do
    ratio = semitones / @pitch_bend_range_semitones
    (8192 + ratio * 8192) |> round() |> max(0) |> min(16_383)
  end

  defp clamp_7bit(value), do: value |> max(0) |> min(127)

  defp midi_note_number({name, octave}) do
    semitone = Enum.find_index(Key.notes(), &(&1 == name))
    (octave + 1) * 12 + semitone
  end

  # MIDI variable-length quantity: 7 data bits per byte, most significant
  # group first, with the continuation bit (0x80) set on every byte but
  # the last.
  defp vlq(0), do: <<0>>

  defp vlq(value) when is_integer(value) and value > 0 do
    value
    |> base128_digits()
    |> mark_continuation()
    |> :erlang.list_to_binary()
  end

  defp base128_digits(0), do: []
  defp base128_digits(value), do: base128_digits(div(value, 128)) ++ [rem(value, 128)]

  defp mark_continuation(digits) do
    last_index = length(digits) - 1

    digits
    |> Enum.with_index()
    |> Enum.map(fn
      {digit, ^last_index} -> digit
      {digit, _index} -> digit + 0x80
    end)
  end
end
