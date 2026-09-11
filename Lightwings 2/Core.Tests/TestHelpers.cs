using System;
using System.IO;

namespace Lightship.Core.Tests
{
    public static class TestHelpers
    {
        /// <summary>Walk up from the test assembly until Lightship.sln is found.</summary>
        public static string RepoRoot()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 12 && dir != null; i++)
            {
                if (File.Exists(Path.Combine(dir, "Lightship.sln"))) return dir;
                dir = Path.GetDirectoryName(dir);
            }
            throw new InvalidOperationException("Lightship.sln not found above " + AppContext.BaseDirectory);
        }

        /// <summary>The canonical ship files, shared with the Godot project and the CLI.</summary>
        public static string ShipsDir() => Path.Combine(RepoRoot(), "GodotProject", "data", "ships");
    }
}
