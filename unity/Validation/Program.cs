using DeskMayhem.UnityBattle;
using UnityEngine;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var sim = new BattleSimulation();
sim.SetActive(0, true);
sim.SetActive(1, true);
var a = sim.State.First;
var b = sim.State.Second;
a.Position = new Vector3(-1, .96f, 0);
b.Position = new Vector3(1, .96f, 0);
sim.State.First = a;
sim.State.Second = b;
BattleState before = sim.State;
sim.Step(new BattleInput { Sequence = 1, SpinSequence = 1, AimX = 1 }, default);
for (int i = 0; i < 14; i++) sim.Step(default, default);
Check(sim.State.Second.Health == 75, "Spin should hit once after windup");
sim.Step(default, default);
Check(sim.State.Second.Health == 75, "Spin must not hit twice");
sim.Step(new BattleInput { Sequence = 2, SpinSequence = 2, AimX = 1 }, default);
for (int i = 0; i < 14; i++) sim.Step(default, default);
Check(sim.State.Second.Health == 75, "Cooldown must reject second spin");
var replay = new BattleSimulation();
replay.Restore(before);
replay.Step(new BattleInput { Sequence = 1, SpinSequence = 1, AimX = 1 }, default);
for (int i = 0; i < 14; i++) replay.Step(default, default);
Check(replay.State.Second.Health == 75 && replay.State.Tick == 15, "Restore and replay should reproduce hit");
var simultaneous = new BattleSimulation();
simultaneous.SetActive(0, true);
simultaneous.SetActive(1, true);
var left = simultaneous.State.First;
var right = simultaneous.State.Second;
left.Position = new Vector3(-1, .96f, 0);
right.Position = new Vector3(1, .96f, 0);
simultaneous.State.First = left;
simultaneous.State.Second = right;
simultaneous.Step(new BattleInput { Sequence = 1, SpinSequence = 1 },
                  new BattleInput { Sequence = 1, SpinSequence = 1 });
for (int i = 0; i < 14; i++) simultaneous.Step(default, default);
Check(simultaneous.State.First.Health == 75 && simultaneous.State.Second.Health == 75,
    "Same-tick spins should both hit");

var respawn = new BattleSimulation();
respawn.SetActive(0, true);
respawn.SetActive(1, true);
left = respawn.State.First;
right = respawn.State.Second;
left.Position = new Vector3(-1, .96f, 0);
right.Position = new Vector3(1, .96f, 0);
right.Health = 25;
respawn.State.First = left;
respawn.State.Second = right;
respawn.Step(new BattleInput { Sequence = 1, SpinSequence = 1 }, default);
for (int i = 0; i < 14; i++) respawn.Step(default, default);
Check(respawn.State.Second.Health == 0, "Lethal spin should kill");
for (int i = 0; i < 180; i++) respawn.Step(default, default);
Check(respawn.State.Second.Health == 100 && respawn.State.Second.Life == 3 &&
    respawn.State.Second.Position.x > 0f, "Second player should respawn in own slot");

var boundary = new BattleSimulation();
boundary.SetActive(0, true);
left = boundary.State.First;
left.Position = new Vector3(52f, .96f, 0);
boundary.State.First = left;
boundary.Step(new BattleInput { Sequence = 1, MoveX = 1 }, default);
for (int i = 0; i < 60; i++) boundary.Step(default, default);
Check(boundary.State.First.Position.x <= 52.55f, "Arena wall must block movement");
Console.WriteLine("BattleSimulation validation passed");
