# ChordSpec User Guide

This guide explains the high-level chord interface for `Mensch.ChordSpec`.

## Recommended authoring style (high-level)

Use `quality` and let tones be resolved internally.

```elixir
%Mensch.ChordSpec{
  root: :c,
  quality: :min7,
  octave: 3,
  inversion: 0,
  bass: nil,
  function: "ii",
  key: %{tonic: :b_flat, mode: :major}
}
```

This resolves internally to tones `"1", "b3", "5", "b7"` and renders as `Cm7`.

## Fields

- `root`: pitch class (supports sharp and flat spellings)
- `quality`: high-level chord quality (preferred)
- `tones`: optional explicit degree list override (advanced)
- `octave`: root anchor octave
- `inversion`: upper-structure inversion
- `bass`: optional slash-bass note
- `function`: optional harmonic-function metadata like `"ii"`, `"V/vi"`
- `key`: optional key metadata like `%{tonic: :b_flat, mode: :major}`

Resolution rule:

- If `tones` is present and non-empty, `tones` wins.
- Otherwise tones are derived from `quality`.

## Supported qualities

- `:maj` -> `1 3 5`
- `:min` -> `1 b3 5`
- `:maj7` -> `1 3 5 7`
- `:min7` -> `1 b3 5 b7`
- `:dom7` -> `1 3 5 b7`
- `:sus2` -> `1 2 5`
- `:sus4` -> `1 4 5`
- `:maj9` -> `1 3 5 7 9`
- `:min9` -> `1 b3 5 b7 9`
- `:dom9` -> `1 3 5 b7 9`
- `:maj11` -> `1 3 5 7 9 11`
- `:min11` -> `1 b3 5 b7 9 11`
- `:dom13` -> `1 3 5 b7 9 13`
- `:six_nine` -> `1 3 5 6 9`
- `:min6` -> `1 b3 5 6`
- `:dim` -> `1 b3 b5`
- `:half_dim` -> `1 b3 b5 b7` (m7b5)
- `:dim7` -> `1 b3 b5 bb7`
- `:aug` -> `1 3 #5`
- `:min7_add11` -> `1 b3 5 b7 11`

## Name-to-spec examples

- `C` -> `root: :c, quality: :maj`
- `Cm7` -> `root: :c, quality: :min7`
- `Cmaj9` -> `root: :c, quality: :maj9`
- `C6/9` -> `root: :c, quality: :six_nine`
- `G7` -> `root: :g, quality: :dom7`
- `G13` -> `root: :g, quality: :dom13`
- `Bdim` -> `root: :b, quality: :dim`
- `Bm7b5` -> `root: :b, quality: :half_dim`
- `Bdim7` -> `root: :b, quality: :dim7`
- `Em7(add11)` -> `root: :e, quality: :min7_add11`

## Slash bass (alternate bass)

Example `C/A`:

```elixir
%Mensch.ChordSpec{
  root: :c,
  quality: :maj,
  bass: :a,
  octave: 3,
  inversion: 0
}
```

Behavior:

- Inversion rotates upper chord tones.
- Slash bass is anchored independently.

## Key and function metadata

These are optional metadata fields.

```elixir
%Mensch.ChordSpec{
  root: :c,
  quality: :min7,
  octave: 3,
  inversion: 0,
  function: "ii",
  key: %{tonic: :b_flat, mode: :major}
}
```

This describes `Cm7` functioning as `ii` in `Bb major`.

## Flat/sharp spelling tips

- For flat keys, prefer flat roots: `:b_flat`, `:e_flat`, `:a_flat`.
- For sharp keys, prefer sharp roots: `:f_sharp`, `:c_sharp`.
- Spelling affects notation/labels, not MIDI pitch.

## Advanced: explicit tones override

If you need custom or unusual voicings, pass `tones` explicitly:

```elixir
%Mensch.ChordSpec{
  root: :g,
  tones: ["1", "3", "b5", "b7", "#9"],
  octave: 3,
  inversion: 0
}
```
