using System;
namespace UnityEngine
{
    public struct Vector2
    {
        public float x, y;
        public Vector2(float x, float y) { this.x = x; this.y = y; }
        public static Vector2 ClampMagnitude(Vector2 value, float maximum)
        {
            float length = MathF.Sqrt(value.x * value.x + value.y * value.y);
            return length > maximum ? new Vector2(value.x * maximum / length, value.y * maximum / length) : value;
        }
    }
    public struct Vector3
    {
        public float x, y, z;
        public Vector3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public static Vector3 zero => new Vector3(0, 0, 0);
        public float sqrMagnitude => x * x + y * y + z * z;
        public Vector3 normalized => sqrMagnitude < .000001f ? zero : this / MathF.Sqrt(sqrMagnitude);
        public static Vector3 operator +(Vector3 a, Vector3 b) => new Vector3(a.x + b.x, a.y + b.y, a.z + b.z);
        public static Vector3 operator -(Vector3 a, Vector3 b) => new Vector3(a.x - b.x, a.y - b.y, a.z - b.z);
        public static Vector3 operator *(Vector3 a, float b) => new Vector3(a.x * b, a.y * b, a.z * b);
        public static Vector3 operator /(Vector3 a, float b) => new Vector3(a.x / b, a.y / b, a.z / b);
        public static float Distance(Vector3 a, Vector3 b) => MathF.Sqrt((a - b).sqrMagnitude);
        public static Vector3 MoveTowards(Vector3 current, Vector3 target, float distance)
        {
            Vector3 change = target - current;
            float length = MathF.Sqrt(change.sqrMagnitude);
            return length <= distance || length == 0 ? target : current + change * (distance / length);
        }
    }
    public static class Mathf
    {
        public static float Abs(float value) => MathF.Abs(value);
        public static float Max(float a, float b) => MathF.Max(a, b);
        public static int Max(int a, int b) => Math.Max(a, b);
        public static float Clamp(float value, float lower, float upper) => Math.Clamp(value, lower, upper);
    }
}
