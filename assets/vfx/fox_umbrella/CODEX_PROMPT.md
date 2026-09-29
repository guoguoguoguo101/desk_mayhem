# Desk Mayhem — 灵狐旋伞 VFX implementation

Use the PNG assets in this pack. Do not redraw or replace them.

Create `FoxUmbrellaSpiritVFX.tscn` as a reusable Godot 4 VFX scene.

Core sequence:
- 0.00s: umbrella spin begins, no fox visible
- 0.08s: spin_ring fades/scales in
- 0.18s: fox_01/02 emerge from behind the player
- 0.30–1.20s: fox frames move on a non-circular 3D S-curve around the player; use scale for depth
- Use fox_04–fox_09 for jump/fly/turn/dive/sweep motion
- 1.05s: use fox_10_attack + energy_arc/energy_slash
- 1.15s: fox_11_tail_sweep
- 1.30s: fox_12_dissolve
- 1.32s: hit_ring + impact_flash + impact_burst + sparks
- 1.50–1.60s: all VFX fade out

Technical direction:
- Sprite3D / camera-facing quads for fox frames
- AnimationPlayer or Tweens for position, scale, opacity and rotation
- GPUParticles3D only for small sparks/petals; do not overfill the screen
- Additive/emission/unshaded materials for glow VFX
- Keep the fox readable; never cover the player
- Do not make the fox orbit at constant angular velocity
- Expose play(), stop(), hit(), reset()
- Do not modify combat hit detection in this task
