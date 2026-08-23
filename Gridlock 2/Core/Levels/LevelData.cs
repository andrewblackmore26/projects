using System.Collections.Generic;

namespace Gridlock.Core.Levels
{
    /// <summary>One node entry as authored in level JSON (spec §10.1).</summary>
    public class LevelNodeData
    {
        public int Id;
        public int Q;
        public int R;
        /// <summary>"player" | "ai" | "neutral".</summary>
        public string Owner;
        /// <summary>Optional starting charge for owned nodes (default 0).</summary>
        public float Charge;
    }

    /// <summary>One wire entry as authored in level JSON. Path is inclusive of both anchor corners.</summary>
    public class LevelWireData
    {
        public int Id;
        public int A;
        public int B;
        /// <summary>Lattice vertex coordinates [n, m] from A to B. Length/degree/faces are computed on load, never authored.</summary>
        public List<VertexCoord> Path = new List<VertexCoord>();
    }

    /// <summary>
    /// Deserialized level file. `LevelLoader` is the single validator — nothing
    /// else in the game may accept a board that did not pass it.
    /// </summary>
    public class LevelData
    {
        public const int FormatVersion = 1;

        public string Id = "";
        public string Name = "";
        public int Difficulty = 1;
        public ObjectiveType Objective = ObjectiveType.Eliminate;

        /// <summary>Par completion time. Unit: seconds. Presentation/scoring only.</summary>
        public float ParTime;

        /// <summary>Survive objective: seconds the player must hold at least one node.</summary>
        public float ObjectiveSeconds;

        /// <summary>Capture objective: node ids the player must own simultaneously.</summary>
        public List<int> ObjectiveNodeIds = new List<int>();

        /// <summary>Efficiency objective: maximum player sends.</summary>
        public int ObjectiveMaxSends;

        /// <summary>Presentation scale hint: screen pixels per lattice unit.</summary>
        public float HexSize = 48f;

        public List<LevelNodeData> Nodes = new List<LevelNodeData>();
        public List<LevelWireData> Wires = new List<LevelWireData>();
    }
}
