using System.Collections.Generic;

namespace Gridlock.Core.Levels
{
    /// <summary>
    /// Serializes LevelData to the on-disk JSON format. Output always round-trips
    /// through LevelLoader (tooling writes, then re-loads to validate).
    /// </summary>
    public static class LevelWriter
    {
        public static string Write(LevelData level)
        {
            var root = new Dictionary<string, object>
            {
                ["version"] = LevelData.FormatVersion,
                ["id"] = level.Id,
                ["name"] = level.Name,
                ["difficulty"] = level.Difficulty,
                ["objective"] = ObjectiveName(level.Objective),
                ["parTime"] = level.ParTime,
                ["hexSize"] = level.HexSize,
            };
            if (level.Objective == ObjectiveType.Survive) root["objectiveSeconds"] = level.ObjectiveSeconds;
            if (level.Objective == ObjectiveType.Efficiency) root["objectiveMaxSends"] = level.ObjectiveMaxSends;
            if (level.ObjectiveNodeIds.Count > 0)
            {
                var ids = new List<object>();
                foreach (int id in level.ObjectiveNodeIds) ids.Add(id);
                root["objectiveNodeIds"] = ids;
            }

            var nodes = new List<object>();
            foreach (LevelNodeData n in level.Nodes)
            {
                var entry = new Dictionary<string, object>
                {
                    ["id"] = n.Id,
                    ["q"] = n.Q,
                    ["r"] = n.R,
                    ["owner"] = n.Owner,
                };
                if (n.Charge > 0f) entry["charge"] = n.Charge;
                nodes.Add(entry);
            }
            root["nodes"] = nodes;

            var wires = new List<object>();
            foreach (LevelWireData w in level.Wires)
            {
                var path = new List<object>();
                foreach (VertexCoord v in w.Path)
                    path.Add(new List<object> { v.N, v.M });
                wires.Add(new Dictionary<string, object>
                {
                    ["id"] = w.Id,
                    ["a"] = w.A,
                    ["b"] = w.B,
                    ["path"] = path,
                });
            }
            root["wires"] = wires;

            return MiniJson.Write(root) + "\n";
        }

        public static string ObjectiveName(ObjectiveType o)
        {
            switch (o)
            {
                case ObjectiveType.Survive: return "survive";
                case ObjectiveType.Capture: return "capture";
                case ObjectiveType.Efficiency: return "efficiency";
                default: return "eliminate";
            }
        }
    }
}
