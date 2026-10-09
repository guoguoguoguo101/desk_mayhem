using System;
using System.Collections.Generic;
using FishNet;
using FishNet.Broadcast;
using FishNet.Connection;
using FishNet.Managing;
using FishNet.Managing.Object;
using FishNet.Managing.Transporting;
using FishNet.Transporting;
using FishNet.Transporting.Tugboat;
using UnityEngine;

namespace DeskMayhem.UnityBattle
{
    public struct InputMessage : IBroadcast { public BattleInput Input; }
    public struct SnapshotMessage : IBroadcast { public BattleState State; }
    public struct WelcomeMessage : IBroadcast { public int Slot; public BattleState State; }

    public sealed class BattleNetwork : MonoBehaviour
    {
        private readonly NetworkConnection[] _players = new NetworkConnection[2];
        private readonly BattleInput[] _control = new BattleInput[2];
        private readonly int[] _lastSpinReceived = new int[2];
        private readonly SortedDictionary<int, BattleInput>[] _queuedMoves =
        {
            new SortedDictionary<int, BattleInput>(), new SortedDictionary<int, BattleInput>()
        };
        private readonly SortedDictionary<int, int>[] _queuedSpins =
        {
            new SortedDictionary<int, int>(), new SortedDictionary<int, int>()
        };
        private readonly List<BattleInput> _history = new List<BattleInput>();
        private readonly BattleSimulation _simulation = new BattleSimulation();
        private NetworkManager _network;
        private BattleState _authority;
        private int _slot = -1;
        private int _inputSequence;
        private int _spinSequence;
        private int _lastSnapshotTick = -1;
        private bool _spinPressed;
        private bool _serverMode;
        private bool _smoke;
        private bool _seenSnapshot;
        private bool _smokeCloseTriggered;
        private string _status = "未连接";
        private string _address = "127.0.0.1";
        private string _port = "24681";
        private BattleView _view;

        public BattleState Predicted => _simulation.State;
        public BattleState Authority => _authority;
        public int Slot => _slot;
        public string Status => _status;
        public float LastCorrection { get; private set; }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void CreateRuntime()
        {
            GameObject host = new GameObject("Battle Runtime");
            host.SetActive(false);
            Tugboat tugboat = host.AddComponent<Tugboat>();
            TransportManager transport = host.AddComponent<TransportManager>();
            transport.Transport = tugboat;
            NetworkManager manager = host.AddComponent<NetworkManager>();
            manager.SpawnablePrefabs = ScriptableObject.CreateInstance<SinglePrefabObjects>();
            host.AddComponent<BattleNetwork>();
            host.SetActive(true);
            DontDestroyOnLoad(host);
        }

        private void Awake()
        {
            _network = GetComponent<NetworkManager>();
            _network.ServerManager.SetStartOnHeadless(false);
            Time.fixedDeltaTime = 1f / BattleSimulation.TicksPerSecond;
            Application.targetFrameRate = 120;
        }

        private void Start()
        {
            _network.ServerManager.RegisterBroadcast<InputMessage>(OnServerInput);
            _network.ClientManager.RegisterBroadcast<WelcomeMessage>(OnWelcome);
            _network.ClientManager.RegisterBroadcast<SnapshotMessage>(OnSnapshot);
            _network.ServerManager.OnAuthenticationResult += OnServerAuthenticated;
            _network.ServerManager.OnRemoteConnectionState += OnRemoteState;
            _network.ClientManager.OnAuthenticated += OnClientAuthenticated;
            _network.ClientManager.OnClientConnectionState += OnClientState;

            _network.TimeManager.SetTickRate(BattleSimulation.TicksPerSecond);
            _serverMode = HasArgument("--server") || (Application.isBatchMode && !HasArgument("--client"));
            _smoke = HasArgument("--smoke");
            if (_serverMode)
            {
                ushort port = ReadPortArgument();

                if (!_network.ServerManager.Started)
                    _network.ServerManager.StartConnection(port);
                _status = "战斗服监听 UDP " + port;
                Debug.Log(_status);
            }
            else
            {
                _view = new GameObject("Arena View").AddComponent<BattleView>();
                _view.Initialize(this);
                if (HasArgument("--client")) Connect(ReadArgument("--connect", "127.0.0.1"), ReadPortArgument().ToString());
            }
        }

        private void OnDestroy()
        {
            if (_network == null) return;
            _network.ServerManager.UnregisterBroadcast<InputMessage>(OnServerInput);
            _network.ClientManager.UnregisterBroadcast<WelcomeMessage>(OnWelcome);
            _network.ClientManager.UnregisterBroadcast<SnapshotMessage>(OnSnapshot);
            _network.ServerManager.OnAuthenticationResult -= OnServerAuthenticated;
            _network.ServerManager.OnRemoteConnectionState -= OnRemoteState;
            _network.ClientManager.OnAuthenticated -= OnClientAuthenticated;
            _network.ClientManager.OnClientConnectionState -= OnClientState;
        }

        private static bool HasArgument(string value)
        {
            foreach (string argument in Environment.GetCommandLineArgs())
                if (argument == value) return true;
            return false;
        }

        private static string ReadArgument(string key, string fallback)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i + 1 < args.Length; i++)
                if (args[i] == key) return args[i + 1];
            return fallback;
        }

        private static ushort ReadPortArgument()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i + 1 < args.Length; i++)
                if (args[i] == "--port" && ushort.TryParse(args[i + 1], out ushort parsed))
                    return parsed;
            return 24681;
        }

        private void OnServerAuthenticated(NetworkConnection connection, bool authenticated)
        {
            if (!_serverMode || !authenticated) return;
            int slot = _players[0] == null ? 0 : _players[1] == null ? 1 : -1;
            if (slot < 0)
            {
                connection.Disconnect(true);
                return;
            }
            _players[slot] = connection;
            _control[slot] = default;
            _queuedMoves[slot].Clear();
            _queuedSpins[slot].Clear();
            _lastSpinReceived[slot] = 0;
            _simulation.SetActive(slot, true);
            connection.Broadcast(new WelcomeMessage { Slot = slot, State = _simulation.State });
            Debug.Log("Player joined slot " + slot);
        }

        private void OnRemoteState(NetworkConnection connection, RemoteConnectionStateArgs args)
        {
            if (!_serverMode || args.ConnectionState != RemoteConnectionState.Stopped) return;
            for (int slot = 0; slot < 2; slot++)
            {
                if (_players[slot] != connection) continue;
                _players[slot] = null;
                _control[slot] = default;
                _queuedMoves[slot].Clear();
                _queuedSpins[slot].Clear();
                _simulation.SetActive(slot, false);
                Debug.Log("Player left slot " + slot);
            }
        }

        private static bool Valid(float value)
        {
            return !float.IsNaN(value) && !float.IsInfinity(value) && Mathf.Abs(value) <= 1.01f;
        }

        private void OnServerInput(NetworkConnection connection, InputMessage message, Channel channel)
        {
            int slot = _players[0] == connection ? 0 : _players[1] == connection ? 1 : -1;
            if (slot < 0) return;
            BattleInput input = message.Input;
            if (input.Sequence == 1) Debug.Log("First input from slot " + slot + " life=" + input.Life + " tick=" + input.Tick);
            if (input.Life != _simulation.State.Get(slot).Life ||
                input.Tick < _simulation.State.Tick - 180 || input.Tick > _simulation.State.Tick + 18 ||
                !Valid(input.MoveX) || !Valid(input.MoveZ) || !Valid(input.AimX) || !Valid(input.AimZ)) return;
            int dueTick = Mathf.Max(input.Tick, _simulation.State.Tick + 1);
            if (input.Sequence > _control[slot].Sequence &&
                input.Sequence < _control[slot].Sequence + 120)
            {
                input.SpinSequence = 0;
                if (!_queuedMoves[slot].TryGetValue(dueTick, out BattleInput previous) ||
                    input.Sequence > previous.Sequence)
                    _queuedMoves[slot][dueTick] = input;
                while (_queuedMoves[slot].Count > 32)
                    _queuedMoves[slot].Remove(FirstKey(_queuedMoves[slot]));
            }
            if (message.Input.SpinSequence > _lastSpinReceived[slot] &&
                message.Input.SpinSequence < _lastSpinReceived[slot] + 120)
            {
                while (_queuedSpins[slot].ContainsKey(dueTick)) dueTick++;
                if (dueTick <= _simulation.State.Tick + 18)
                {
                    _lastSpinReceived[slot] = message.Input.SpinSequence;
                    _queuedSpins[slot][dueTick] = message.Input.SpinSequence;
                }
            }
        }

        private static int FirstKey<T>(SortedDictionary<int, T> dictionary)
        {
            foreach (int key in dictionary.Keys) return key;
            return 0;
        }

        private BattleInput DueInput(int slot, int tick)
        {
            var dueMoves = new List<int>();
            foreach (var pair in _queuedMoves[slot])
            {
                if (pair.Key > tick) break;
                if (pair.Value.Sequence > _control[slot].Sequence)
                    _control[slot] = pair.Value;
                dueMoves.Add(pair.Key);
            }
            foreach (int key in dueMoves) _queuedMoves[slot].Remove(key);
            BattleInput current = _control[slot];
            current.SpinSequence = 0;
            int spinTick = -1;
            foreach (var pair in _queuedSpins[slot])
            {
                if (pair.Key > tick) break;
                current.SpinSequence = pair.Value;
                spinTick = pair.Key;
                break;
            }
            if (spinTick >= 0) _queuedSpins[slot].Remove(spinTick);
            return current;
        }
        private void OnClientState(ClientConnectionStateArgs args)
        {
            if (args.ConnectionState != LocalConnectionState.Stopped) return;
            _slot = -1;
            _history.Clear();
            _status = "连接已断开";
        }

        private void OnClientAuthenticated()
        {
            _status = "已连接，等待入场";
            Debug.Log(_status);
        }

        private void OnWelcome(WelcomeMessage message, Channel channel)
        {
            if (_serverMode) return;
            _slot = message.Slot;
            _authority = message.State;
            _lastSnapshotTick = message.State.Tick;
            _simulation.Restore(message.State);
            _history.Clear();
            _inputSequence = message.State.Get(_slot).LastInputSequence;
            _spinSequence = message.State.Get(_slot).LastSpinSequence;
            _status = "已入场，玩家 " + (_slot + 1);
            Debug.Log(_status + " tick=" + message.State.Tick);
        }

        private void OnSnapshot(SnapshotMessage message, Channel channel)
        {
            if (_serverMode || _slot < 0 || message.State.Tick <= _lastSnapshotTick) return;
            if (!_seenSnapshot) { Debug.Log("First snapshot tick=" + message.State.Tick + " slot=" + _slot); _seenSnapshot = true; }
            int oldTick = _simulation.State.Tick;
            Vector3 before = _simulation.State.Get(_slot).Position;
            _authority = message.State;
            _lastSnapshotTick = message.State.Tick;
            FighterState own = message.State.Get(_slot);
            if (own.Life != _simulation.State.Get(_slot).Life) _history.Clear();
            _history.RemoveAll(frame => frame.Sequence <= own.LastInputSequence &&
                                        frame.SpinSequence <= own.LastSpinSequence);
            _simulation.Restore(message.State);
            int horizon = Mathf.Min(Mathf.Max(oldTick, message.State.Tick + 2), message.State.Tick + 12);
            int historyIndex = 0;
            for (int tick = message.State.Tick + 1; tick <= horizon; tick++)
            {
                BattleInput replay = default;
                if (historyIndex < _history.Count && _history[historyIndex].Tick <= tick)
                {
                    replay = _history[historyIndex++];
                    if (replay.Sequence <= own.LastInputSequence) replay.Sequence = 0;
                    if (replay.SpinSequence <= own.LastSpinSequence) replay.SpinSequence = 0;
                }
                if (_slot == 0) _simulation.Step(replay, default);
                else _simulation.Step(default, replay);
            }
            LastCorrection = oldTick == horizon && oldTick >= message.State.Tick
                ? Vector3.Distance(before, _simulation.State.Get(_slot).Position) : 0f;
        }

        private void Update()
        {
            if (!_serverMode && _slot >= 0 && Input.GetKeyDown(KeyCode.E))
                _spinPressed = true;
        }

        private void FixedUpdate()
        {
            if (_serverMode)
            {
                if (!_network.ServerManager.Started) return;
                int life0 = _simulation.State.First.Life;
                int life1 = _simulation.State.Second.Life;
                BattleInput first = DueInput(0, _simulation.State.Tick + 1);
                BattleInput second = DueInput(1, _simulation.State.Tick + 1);
                int health0 = _simulation.State.First.Health;
                int health1 = _simulation.State.Second.Health;
                _simulation.Step(first, second);
                if (_simulation.State.Tick % 120 == 0) Debug.Log("Server tick " + _simulation.State.Tick + " x=" + _simulation.State.First.Position.x.ToString("F1") + "/" + _simulation.State.Second.Position.x.ToString("F1"));
                if (_simulation.State.First.Health != health0 || _simulation.State.Second.Health != health1)
                    Debug.Log("Authoritative health: " + _simulation.State.First.Health + "/" + _simulation.State.Second.Health + " at tick " + _simulation.State.Tick);
                if (_simulation.State.First.Life != life0) { _control[0].MoveX = 0f; _control[0].MoveZ = 0f; _queuedMoves[0].Clear(); _queuedSpins[0].Clear(); }
                if (_simulation.State.Second.Life != life1) { _control[1].MoveX = 0f; _control[1].MoveZ = 0f; _queuedMoves[1].Clear(); _queuedSpins[1].Clear(); }
                if (_simulation.State.Tick % 2 == 0)
                {
                    SnapshotMessage snapshot = new SnapshotMessage { State = _simulation.State };
                    for (int slot = 0; slot < 2; slot++)
                        if (_players[slot] != null)
                            _players[slot].Broadcast(snapshot, true, Channel.Unreliable);
                }
                return;
            }
            if (_slot < 0 || !_network.ClientManager.Started) return;
            if (_simulation.State.Tick >= _lastSnapshotTick + 12) return;
            BattleInput input = _smoke ? new BattleInput { MoveX = _slot == 0 ? 1f : -1f, AimX = _slot == 0 ? 1f : -1f } : _view.SampleInput();
            if (_smoke && !_smokeCloseTriggered &&
                Vector3.Distance(_simulation.State.First.Position, _simulation.State.Second.Position) <= 2.4f)
            {
                _spinPressed = true;
                _smokeCloseTriggered = true;
            }
            input.Sequence = ++_inputSequence;
            input.Life = _simulation.State.Get(_slot).Life;
            input.Tick = _simulation.State.Tick + 1;
            if (_spinPressed)
            {
                input.SpinSequence = ++_spinSequence;
                _spinPressed = false;
            }
            if (_smoke && input.Sequence == 1) Debug.Log("First local input slot=" + _slot + " tick=" + input.Tick);
            _history.Add(input);
            if (_history.Count > 128) _history.RemoveAt(0);
            if (_slot == 0) _simulation.Step(input, default);
            else _simulation.Step(default, input);
            _network.ClientManager.Broadcast(new InputMessage { Input = input },
                input.SpinSequence > 0 ? Channel.Reliable : Channel.Unreliable);
        }

        public void Connect(string address, string port)
        {
            if (_serverMode || _network.ClientManager.Started) return;
            if (!ushort.TryParse(port, out ushort parsed)) { _status = "端口无效"; return; }
            _status = "连接 " + address + ":" + parsed;
            if (!_network.ClientManager.StartConnection(address, parsed)) _status = "连接启动失败";
        }

        private void OnGUI()
        {
            if (_serverMode) return;
            GUILayout.BeginArea(new Rect(15, 15, 330, 160), GUI.skin.box);
            GUILayout.Label("山门演武场 · 第一阶段");
            if (_slot < 0)
            {
                GUILayout.BeginHorizontal();
                _address = GUILayout.TextField(_address, GUILayout.Width(210));
                _port = GUILayout.TextField(_port, GUILayout.Width(80));
                GUILayout.EndHorizontal();
                if (GUILayout.Button("连接战斗服")) Connect(_address, _port);
            }
            else
            {
                FighterState own = _authority.Get(_slot);
                FighterState other = _authority.Get(1 - _slot);
                GUILayout.Label("血量 " + own.Health + " / 对手 " + other.Health);
                GUILayout.Label("WASD 移动 · E 旋伞");
                GUILayout.Label("最近纠偏 " + LastCorrection.ToString("F2") + " 米");
            }
            GUILayout.Label(_status);
            GUILayout.EndArea();
        }
    }
}
