// Test-only native exporter. Its output is text, never a playable Godot pack.
using System;
using System.IO;
using System.Text;
public static class PreparedExporterFixture
{
    public static int Main(string[] args)
    {
        int export = Array.IndexOf(args, "--export-pack"), source = Array.IndexOf(args, "--path");
        if (export < 0 || source < 0) return 23;
        string home = AppDomain.CurrentDomain.BaseDirectory, root = args[source + 1];
        File.WriteAllText(Path.Combine(home, "export-observed.txt"), root);
        if (File.Exists(Path.Combine(home, "mutate-frozen.txt")))
            File.AppendAllText(Path.Combine(root, "client.gd"), "\n# exporter changed input\n");
        if (File.Exists(Path.Combine(home, "mutate-original.txt")))
            File.AppendAllText(File.ReadAllText(Path.Combine(home, "mutate-original.txt")), "\n# original changed during export\n");
        if (File.Exists(Path.Combine(home, "generate-uids.txt"))) {
            Directory.CreateDirectory(Path.Combine(root, ".godot"));
            File.WriteAllText(Path.Combine(root, ".godot", "cache.txt"), "engine cache");
            File.WriteAllText(Path.Combine(root, "client.gd.uid"), "uid://test-generated");
        }
        if (File.Exists(Path.Combine(home, "change-existing-uid.txt")))
            File.WriteAllText(Path.Combine(root, "client.gd.uid"), "uid://changed-existing");
        if (File.Exists(Path.Combine(home, "orphan-uid.txt")))
            File.WriteAllText(Path.Combine(root, "orphan.gd.uid"), "uid://no-frozen-source");
        if (File.Exists(Path.Combine(home, "fail-export.txt"))) return 23;
        File.WriteAllText(args[export + 2], "NOT_A_GODOT_PACK\n" + File.ReadAllText(Path.Combine(root, "client.gd")), Encoding.UTF8);
        return 0;
    }
}
