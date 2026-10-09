using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace DeskMayhem.UnityBattle.Editor
{
    public static class FirstPhaseSetup
    {
        private const string ScenePath = "Assets/Scenes/Arena.unity";

        [InitializeOnLoadMethod]
        private static void OnEditorReady()
        {
            EditorApplication.delayCall += () =>
            {
                if (!File.Exists(ScenePath)) PrepareArenaScene();
            };
        }

        [MenuItem("Desk Mayhem/Prepare Arena Scene")]
        public static void PrepareArenaScene()
        {
            if (!File.Exists(ScenePath))
            {
                Directory.CreateDirectory("Assets/Scenes");
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, ScenePath);
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            EditorSceneManager.OpenScene(ScenePath);
            Debug.Log("Arena scene ready: " + ScenePath);
        }

        [MenuItem("Desk Mayhem/Build Client And Linux Server")]
        public static void BuildBoth()
        {
            PrepareArenaScene();
            Directory.CreateDirectory("Builds/Client");
            Directory.CreateDirectory("Builds/Server");
            var client = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = "Builds/Client/DeskMayhemClient.exe",
                target = BuildTarget.StandaloneWindows64,
                subtarget = (int)StandaloneBuildSubtarget.Player,
                options = BuildOptions.None
            });
            if (client.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
                throw new System.Exception("Windows client build failed: " + client.summary.result);

            var server = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = "Builds/Server/DeskMayhemServer",
                target = BuildTarget.StandaloneLinux64,
                subtarget = (int)StandaloneBuildSubtarget.Server,
                options = BuildOptions.None
            });
            if (server.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
                throw new System.Exception("Linux dedicated server build failed: " + server.summary.result);
            Debug.Log("First-phase client and dedicated server builds completed.");
        }
    }
}
