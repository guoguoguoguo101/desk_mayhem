using System;
using UnityEngine;

namespace DeskMayhem.UnityBattle
{
    [Serializable]
    public struct BattleInput
    {
        public int Sequence;
        public int Life;
        public int Tick;
        public float MoveX;
        public float MoveZ;
        public float AimX;
        public float AimZ;
        public int SpinSequence;
    }

    [Serializable]
    public struct FighterState
    {
        public bool Active;
        public int Slot;
        public Vector3 Position;
        public Vector3 Velocity;
        public Vector3 Facing;
        public float MoveX;
        public float MoveZ;
        public int Health;
        public int Life;
        public int RespawnTick;
        public int StunUntilTick;
        public int SpinHitTick;
        public int SpinEndTick;
        public int SpinReadyTick;
        public int LastInputSequence;
        public int LastSpinSequence;
        public int LastHitSpinSequence;
    }

    [Serializable]
    public struct BattleState
    {
        public int Tick;
        public FighterState First;
        public FighterState Second;

        public FighterState Get(int slot) { return slot == 0 ? First : Second; }
        public void Set(int slot, FighterState value)
        {
            if (slot == 0) First = value;
            else Second = value;
        }
    }

    /// <summary>Only gameplay state lives here. Both client replay and the server call Step.</summary>
    public sealed class BattleSimulation
    {
        public const int TicksPerSecond = 60;
        public const int MaxHealth = 100;
        public const float SpinRadius = 3f;
        public BattleState State;

        private struct Blocker
        {
            public readonly float X, Z, HalfX, HalfZ;
            public Blocker(float x, float z, float halfX, float halfZ)
            { X = x; Z = z; HalfX = halfX; HalfZ = halfZ; }
        }

        // Simplified gameplay blockers from mountain_arena_layout.gd. Art never drives hits.
        private static readonly Blocker[] Blockers =
        {
            new Blocker(0f, -35f, 16f, 4.5f),
            new Blocker(-43f, 2f, 4.5f, 6f),
            new Blocker(43f, 2f, 4.5f, 6f),
            new Blocker(-15f, 38f, 9.5f, 3.5f),
            new Blocker(15f, 38f, 9.5f, 3.5f),
            new Blocker(-29f, -18f, .55f, .55f),
            new Blocker(-29f, 18f, .55f, .55f),
            new Blocker(29f, -18f, .55f, .55f),
            new Blocker(29f, 18f, .55f, .55f)
        };

        public BattleSimulation()
        {
            State = new BattleState
            {
                First = NewFighter(0, false),
                Second = NewFighter(1, false)
            };
        }

        public static FighterState NewFighter(int slot, bool active)
        {
            return new FighterState
            {
                Active = active,
                Slot = slot,
                Position = new Vector3(slot == 0 ? -16f : 16f, .96f, 0f),
                Facing = new Vector3(slot == 0 ? 1f : -1f, 0f, 0f),
                Health = MaxHealth,
                Life = 1
            };
        }

        public void Restore(BattleState state) { State = state; }

        public void SetActive(int slot, bool active)
        {
            FighterState player = NewFighter(slot, active);
            player.Life = State.Get(slot).Life + 1;
            State.Set(slot, player);
        }

        public void Step(BattleInput first, BattleInput second)
        {
            State.Tick++;
            FighterState a = State.First;
            FighterState b = State.Second;
            Advance(ref a, first);
            Advance(ref b, second);

            // Resolve both hits from the same pre-hit world, so mutual hits are possible.
            bool aHits = CanSpinHit(a, b);
            bool bHits = CanSpinHit(b, a);
            if (aHits) ApplyHit(ref b, a.LastSpinSequence);
            if (bHits) ApplyHit(ref a, b.LastSpinSequence);
            State.First = a;
            State.Second = b;
        }

        private void Advance(ref FighterState fighter, BattleInput input)
        {
            if (!fighter.Active) return;
            if (fighter.Health <= 0)
            {
                if (State.Tick >= fighter.RespawnTick)
                {
                    int slot = fighter.Slot;
                    int life = fighter.Life + 1;
                    fighter = NewFighter(slot, true);
                    fighter.Life = life;
                }
                else return;
            }

            if (input.Sequence > fighter.LastInputSequence)
            {
                fighter.LastInputSequence = input.Sequence;
                Vector2 move = Vector2.ClampMagnitude(new Vector2(input.MoveX, input.MoveZ), 1f);
                fighter.MoveX = move.x;
                fighter.MoveZ = move.y;
                Vector3 aim = new Vector3(input.AimX, 0f, input.AimZ);
                if (aim.sqrMagnitude > .01f && aim.sqrMagnitude < 4f)
                    fighter.Facing = aim.normalized;
            }

            if (input.SpinSequence > fighter.LastSpinSequence)
            {
                fighter.LastSpinSequence = input.SpinSequence;
                if (State.Tick >= fighter.SpinReadyTick && State.Tick >= fighter.StunUntilTick)
                {
                    fighter.SpinHitTick = State.Tick + 14;
                    fighter.SpinEndTick = State.Tick + 28;
                    fighter.SpinReadyTick = State.Tick + 132;
                }
            }

            Vector3 desired = new Vector3(fighter.MoveX, 0f, fighter.MoveZ) * 6.5f;
            if (State.Tick < fighter.StunUntilTick) desired = Vector3.zero;
            float acceleration = desired.sqrMagnitude < .01f ? 65f : 46f;
            fighter.Velocity = Vector3.MoveTowards(fighter.Velocity, desired, acceleration / TicksPerSecond);
            Vector3 position = fighter.Position;
            Vector3 delta = fighter.Velocity / TicksPerSecond;
            position.x = Mathf.Clamp(position.x + delta.x, -52.55f, 52.55f);
            if (Blocked(position)) { position.x = fighter.Position.x; fighter.Velocity.x = 0f; }
            position.z = Mathf.Clamp(position.z + delta.z, -42.55f, 42.55f);
            if (Blocked(position)) { position.z = fighter.Position.z; fighter.Velocity.z = 0f; }
            fighter.Position = position;
        }

        private static bool Blocked(Vector3 position)
        {
            const float radius = .45f;
            foreach (Blocker box in Blockers)
            {
                float dx = Mathf.Max(Mathf.Abs(position.x - box.X) - box.HalfX, 0f);
                float dz = Mathf.Max(Mathf.Abs(position.z - box.Z) - box.HalfZ, 0f);
                if (dx * dx + dz * dz < radius * radius) return true;
            }
            return false;
        }

        private bool CanSpinHit(FighterState attacker, FighterState target)
        {
            return attacker.Active && target.Active && attacker.Health > 0 && target.Health > 0
                && attacker.SpinHitTick == State.Tick
                && Vector3.Distance(attacker.Position, target.Position) <= SpinRadius;
        }

        private void ApplyHit(ref FighterState victim, int attackSequence)
        {
            victim.Health = Mathf.Max(0, victim.Health - 25);
            victim.LastHitSpinSequence = attackSequence;
            victim.StunUntilTick = State.Tick + 18;
            if (victim.Health == 0)
            {
                victim.RespawnTick = State.Tick + 180;
                victim.Velocity = Vector3.zero;
            }
        }
    }
}
