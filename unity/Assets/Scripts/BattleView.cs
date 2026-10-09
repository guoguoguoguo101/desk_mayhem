using UnityEngine;

namespace DeskMayhem.UnityBattle
{
    /// <summary>Disposable graybox view. Transforms never feed back into BattleSimulation.</summary>
    public sealed class BattleView : MonoBehaviour
    {
        private BattleNetwork _battle;
        private readonly Transform[] _fighters = new Transform[2];
        private readonly GameObject[] _spinMarkers = new GameObject[2];
        private Camera _camera;
        private float _yaw = 30f;
        private float _pitch = 25f;

        public void Initialize(BattleNetwork battle)
        {
            _battle = battle;
            BuildArena();
            _fighters[0] = MakePrimitive(PrimitiveType.Capsule, "Player 1", new Vector3(-16f, .96f, 0f),
                new Vector3(.9f, .96f, .9f), new Color(.13f, .65f, .96f)).transform;
            _fighters[1] = MakePrimitive(PrimitiveType.Capsule, "Player 2", new Vector3(16f, .96f, 0f),
                new Vector3(.9f, .96f, .9f), new Color(1f, .46f, .28f)).transform;
            for (int i = 0; i < 2; i++)
            {
                _spinMarkers[i] = new GameObject("Spin range " + i);
                _spinMarkers[i].transform.SetParent(_fighters[i], false);
                for (int part = 0; part < 12; part++)
                {
                    float angle = part * Mathf.PI * 2f / 12f;
                    Transform marker = MakePrimitive(PrimitiveType.Cube, "Spin marker", Vector3.zero,
                        new Vector3(.45f, .12f, .18f), new Color(.25f, .95f, .92f)).transform;
                    marker.SetParent(_spinMarkers[i].transform, false);
                    marker.localPosition = new Vector3(Mathf.Cos(angle) * BattleSimulation.SpinRadius,
                        -.77f, Mathf.Sin(angle) * BattleSimulation.SpinRadius);
                    marker.localRotation = Quaternion.Euler(0f, -angle * Mathf.Rad2Deg, 0f);
                }
                _spinMarkers[i].SetActive(false);
            }
            GameObject cameraObject = new GameObject("Battle Camera");
            _camera = cameraObject.AddComponent<Camera>();
            _camera.clearFlags = CameraClearFlags.Skybox;
            _camera.fieldOfView = 58f;

            GameObject sun = new GameObject("Sun");
            Light light = sun.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1.2f;
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            RenderSettings.ambientLight = new Color(.42f, .48f, .57f);
        }

        private static GameObject MakePrimitive(PrimitiveType type, string name, Vector3 position,
            Vector3 scale, Color color)
        {
            GameObject result = GameObject.CreatePrimitive(type);
            result.name = name;
            result.transform.position = position;
            result.transform.localScale = scale;
            Collider collider = result.GetComponent<Collider>();
            if (collider != null) Destroy(collider);
            Renderer renderer = result.GetComponent<Renderer>();
            renderer.material.color = color;
            return result;
        }

        private static void Box(string name, Vector3 center, Vector3 size, Color color)
        {
            MakePrimitive(PrimitiveType.Cube, name, center, size, color);
        }

        private void BuildArena()
        {
            Color stone = new Color(.48f, .51f, .52f);
            Color wall = new Color(.35f, .35f, .4f);
            Color wood = new Color(.46f, .21f, .14f);
            Box("山门演武场 floor", new Vector3(0f, -.2f, 0f), new Vector3(108f, .4f, 88f), stone);
            Box("north wall", new Vector3(0f, 2f, -43.5f), new Vector3(108f, 4f, 1f), wall);
            Box("south wall", new Vector3(0f, 2f, 43.5f), new Vector3(108f, 4f, 1f), wall);
            Box("west wall", new Vector3(-53.5f, 2f, 0f), new Vector3(1f, 4f, 86f), wall);
            Box("east wall", new Vector3(53.5f, 2f, 0f), new Vector3(1f, 4f, 86f), wall);
            Box("main hall", new Vector3(0f, 2f, -35f), new Vector3(32f, 4f, 9f), wood);
            Box("west pavilion", new Vector3(-43f, 1.8f, 2f), new Vector3(9f, 3.6f, 12f), wood);
            Box("east pavilion", new Vector3(43f, 1.8f, 2f), new Vector3(9f, 3.6f, 12f), wood);
            Box("gate west", new Vector3(-15f, 2f, 38f), new Vector3(19f, 4f, 7f), wood);
            Box("gate east", new Vector3(15f, 2f, 38f), new Vector3(19f, 4f, 7f), wood);
            foreach (float x in new[] { -29f, 29f })
                foreach (float z in new[] { -18f, 18f })
                    MakePrimitive(PrimitiveType.Cylinder, "stone lantern", new Vector3(x, .85f, z),
                        new Vector3(1.1f, .85f, 1.1f), new Color(.75f, .68f, .42f));
            MakePrimitive(PrimitiveType.Cylinder, "central arena", new Vector3(0f, .015f, 0f),
                new Vector3(12f, .01f, 12f), new Color(.62f, .58f, .52f));
        }

        public BattleInput SampleInput()
        {
            Vector3 forward = Quaternion.Euler(0f, _yaw, 0f) * Vector3.forward;
            Vector3 right = Quaternion.Euler(0f, _yaw, 0f) * Vector3.right;
            Vector3 move = forward * Input.GetAxisRaw("Vertical") + right * Input.GetAxisRaw("Horizontal");
            if (move.sqrMagnitude > 1f) move.Normalize();
            return new BattleInput
            {
                MoveX = move.x, MoveZ = move.z,
                AimX = forward.x, AimZ = forward.z
            };
        }

        private void Update()
        {
            if (_battle == null) return;
            int ownSlot = _battle.Slot;
            BattleState state = _battle.Predicted;
            for (int i = 0; i < 2; i++)
            {
                FighterState fighter = state.Get(i);
                _fighters[i].gameObject.SetActive(fighter.Active && fighter.Health > 0);
                if (!fighter.Active) continue;
                if (i == ownSlot) _fighters[i].position = fighter.Position;
                else _fighters[i].position = Vector3.Lerp(_fighters[i].position, fighter.Position,
                    Mathf.Clamp01(Time.deltaTime * 12f));
                if (fighter.Facing.sqrMagnitude > .01f)
                    _fighters[i].rotation = Quaternion.LookRotation(fighter.Facing);
                _spinMarkers[i].SetActive(fighter.Health > 0 && state.Tick < fighter.SpinEndTick &&
                    state.Tick >= fighter.SpinHitTick - 14);
            }
            if (ownSlot >= 0)
            {
                if (Input.GetMouseButtonDown(0)) Cursor.lockState = CursorLockMode.Locked;
                if (Input.GetKeyDown(KeyCode.Escape)) Cursor.lockState = CursorLockMode.None;
                if (Cursor.lockState == CursorLockMode.Locked)
                {
                    _yaw += Input.GetAxis("Mouse X") * 3f;
                    _pitch = Mathf.Clamp(_pitch - Input.GetAxis("Mouse Y") * 2f, 10f, 65f);
                }
            }
            Vector3 target = ownSlot < 0 ? Vector3.zero : _fighters[ownSlot].position;
            Quaternion orbit = Quaternion.Euler(_pitch, _yaw, 0f);
            Vector3 goal = target + orbit * new Vector3(0f, 2f, -10f);
            _camera.transform.position = Vector3.Lerp(_camera.transform.position, goal,
                Mathf.Clamp01(Time.deltaTime * 10f));
            _camera.transform.LookAt(target + Vector3.up * 1.1f);
        }
    }
}
