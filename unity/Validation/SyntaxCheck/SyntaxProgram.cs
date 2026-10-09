using System;
using System.IO;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../Assets"));
string[] files = Directory.GetFiles(root, "*.cs", SearchOption.AllDirectories);
int failures = 0;
foreach (string path in files)
{
    var tree = CSharpSyntaxTree.ParseText(File.ReadAllText(path), path: path);
    foreach (var diagnostic in tree.GetDiagnostics().Where(d => d.Severity == DiagnosticSeverity.Error))
    {
        Console.WriteLine(diagnostic);
        failures++;
    }
}
Console.WriteLine($"Parsed {files.Length} Unity C# files; syntax errors: {failures}");
return failures == 0 ? 0 : 1;
