# Interesting Luck Cycle Strategy

This note documents the previous DynamicVoicing cycle strategy (kept for potential reuse in a dedicated machine).

## Previous cycle behavior (step-flip strategy)

Direction modes:
- `{:cycle_up, n}`
- `{:cycle_down, n}`

Meaning of `n` in the previous implementation:
- `n` = number of **voicing steps before flipping direction**.

How it worked:
1. Start from a base direction (`:up` for `:cycle_up`, `:down` for `:cycle_down`).
2. Move in that direction for `n` steps.
3. Flip direction and move for `n` steps.
4. Repeat this alternating pattern.

Equivalent direction stream example:
- `{:cycle_up, 2}` => `up, up, down, down, up, up, down, down, ...`
- `{:cycle_down, 1}` => `down, up, down, up, ...`

Important characteristics:
- Flipping was driven by step count chunks, not by reaching a specific inversion bound.
- The behavior did not require returning to start inversion to complete a cycle.
- It can produce musically interesting roaming motion because turning points are time/step-based.

## Voice-lifecycle pattern observed in charts/audio

The previous strategy was not only a directional pattern. It also created a
very specific "inside stable / outside churning" note-lifecycle shape:

1. Middle voices stayed active for most (sometimes all) of the chord window.
2. Outer voices were swapped more often at inversion boundaries.
3. The farther a voice was from the center register, the shorter its average
	 lifetime became.
4. The most outer voices had the highest turnover rate: frequent note-on/note-off
	 pairs and visibly shorter segments in timeline/matrix views.

In practical terms, this yielded:
- A stable harmonic core (long horizontal bands in the middle of the note matrix).
- Progressive activity toward the edges (more fragmented bands as you move
	outward).
- A "breathing shell" around a held center, which is likely the musical quality
	you noticed.

This behavior emerges from repeatedly replacing the edge note implied by each
inversion transition while interior tones are often re-used across adjacent
voicings.

## Why keep this note

This behavior is useful as a distinct motion strategy and can be extracted into a dedicated machine in the future.
