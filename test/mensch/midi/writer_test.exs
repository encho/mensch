defmodule Mensch.Midi.WriterTest do
  use ExUnit.Case, async: true

  alias Mensch.Midi.Writer
  alias Mensch.Performance.Event

  @events [
    %Event{type: :note_on, at_beat: 0.0, note: {:d, 3}, velocity: 90},
    %Event{type: :note_off, at_beat: 4.0, note: {:d, 3}},
    %Event{type: :note_on, at_beat: 4.0, note: {:g, 3}, velocity: 90},
    %Event{type: :note_off, at_beat: 8.0, note: {:g, 3}}
  ]

  test "writes a valid Standard MIDI File header (format 0, 1 track, 480 ticks/beat)" do
    assert <<"MThd", 6::32, 0::16, 1::16, 480::16, _rest::binary>> = Writer.encode(@events, 120)
  end

  test "writes a single MTrk chunk whose declared length matches its body" do
    binary = Writer.encode(@events, 120)
    <<_header::binary-size(14), "MTrk", track_length::32, track_body::binary>> = binary

    assert byte_size(track_body) == track_length
  end

  test "encodes a tempo meta event followed by note on/off events with correct note numbers and deltas" do
    binary = Writer.encode(@events, 120)
    <<_header::binary-size(14), "MTrk", _length::32, track_body::binary>> = binary

    assert {decoded, <<>>} = decode_events(track_body)

    assert [
             {0, <<0xFF, 0x51, 3, _tempo::24>>},
             {0, <<0x90, 50, 90>>},
             {1920, <<0x80, 50, 0>>},
             {0, <<0x90, 55, 90>>},
             {1920, <<0x80, 55, 0>>},
             {0, <<0xFF, 0x2F, 0>>}
           ] = decoded
  end

  test "500000 microseconds per quarter note at 120 BPM" do
    binary = Writer.encode(@events, 120)
    <<_header::binary-size(14), "MTrk", _length::32, track_body::binary>> = binary
    {[{0, <<0xFF, 0x51, 3, tempo::24>>} | _rest], <<>>} = decode_events(track_body)

    assert tempo == 500_000
  end

  test "encodes pressure events as channel pressure and pitch bend events as pitch wheel messages" do
    events = [
      %Event{type: :note_on, at_beat: 0.0, note: {:c, 3}, velocity: 100},
      %Event{type: :pressure, at_beat: 1.0, note: {:c, 3}, value: 1.0},
      %Event{type: :pitch_bend, at_beat: 1.0, note: {:c, 3}, value: 0.0},
      %Event{type: :pitch_bend, at_beat: 2.0, note: {:c, 3}, value: 2.0},
      %Event{type: :note_off, at_beat: 4.0, note: {:c, 3}}
    ]

    binary = Writer.encode(events, 120)
    <<_header::binary-size(14), "MTrk", _length::32, track_body::binary>> = binary
    {decoded, <<>>} = decode_events(track_body)

    assert [
             {0, <<0xFF, 0x51, 3, _tempo::24>>},
             {0, <<0x90, 48, 100>>},
             {480, <<0xD0, 127>>},
             {0, <<0xE0, 0, 64>>},
             {480, <<0xE0, lsb, msb>>},
             {960, <<0x80, 48, 0>>},
             {0, <<0xFF, 0x2F, 0>>}
           ] = decoded

    assert msb * 128 + lsb == 16_383
  end

  defp decode_events(binary), do: decode_events(binary, [])

  defp decode_events(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp decode_events(binary, acc) do
    {delta, rest} = decode_vlq(binary, 0)
    {event_bytes, rest} = take_event(rest)
    decode_events(rest, [{delta, event_bytes} | acc])
  end

  defp decode_vlq(<<0::1, byte::7, rest::binary>>, acc), do: {acc * 128 + byte, rest}

  defp decode_vlq(<<1::1, byte::7, rest::binary>>, acc) do
    decode_vlq(rest, acc * 128 + byte)
  end

  defp take_event(<<0xFF, type, length, data::binary-size(length), rest::binary>>) do
    {<<0xFF, type, length, data::binary>>, rest}
  end

  defp take_event(<<status, a, b, rest::binary>>) when status in [0x80, 0x90, 0xE0] do
    {<<status, a, b>>, rest}
  end

  defp take_event(<<0xD0, a, rest::binary>>) do
    {<<0xD0, a>>, rest}
  end
end
