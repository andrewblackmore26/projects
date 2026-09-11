using System;
using System.Collections.Generic;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;

namespace Lightship.Core.World
{
    /// <summary>A sector's place in the grid. The origin is (0, 0); +x east, +y south (screen down).</summary>
    public readonly struct SectorCoord : IEquatable<SectorCoord>
    {
        public readonly int X, Y;
        public SectorCoord(int x, int y) { X = x; Y = y; }

        /// <summary>Spec 7: sectors are arranged in layers outward from the origin (Chebyshev rings).</summary>
        public int Layer => Math.Max(Math.Abs(X), Math.Abs(Y));
        public SectorCoord Step(Edge e) => e switch
        {
            Edge.North => new SectorCoord(X, Y - 1),
            Edge.South => new SectorCoord(X, Y + 1),
            Edge.West => new SectorCoord(X - 1, Y),
            _ => new SectorCoord(X + 1, Y),
        };
        public static int Distance(SectorCoord a, SectorCoord b) => Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));

        public bool Equals(SectorCoord o) => X == o.X && Y == o.Y;
        public override bool Equals(object obj) => obj is SectorCoord c && Equals(c);
        public override int GetHashCode() => X * 397 ^ Y;
        public static bool operator ==(SectorCoord a, SectorCoord b) => a.Equals(b);
        public static bool operator !=(SectorCoord a, SectorCoord b) => !a.Equals(b);
        public override string ToString() => "(" + X + "," + Y + ")";
    }

    public enum Edge { North, East, South, West }

    public static class Edges
    {
        public static Edge Opposite(Edge e) => (Edge)(((int)e + 2) % 4);
        public static readonly Edge[] All = { Edge.North, Edge.East, Edge.South, Edge.West };
    }

    /// <summary>Permanent facts about a sector (its identity and role); per-life state lives in the run.</summary>
    public sealed class Sector
    {
        public SectorCoord Coord;
        public int Layer => Coord.Layer;
        /// <summary>The rival AI that owns it (its light type, its enemies). None for the origin.</summary>
        public Element Owner;
        public bool IsGate;
        /// <summary>The gatekeeper's design, for gate sectors (a rival-class boss, spec 7).</summary>
        public string GatekeeperShip;
        /// <summary>Tier of the regular enemies here (spec 8: scales with the layer, not the clock).</summary>
        public int EnemyTier;
        /// <summary>Regular enemies to beat before the sector counts as cleared.</summary>
        public int EnemyCount;

        /// <summary>The strongest thing in the sector: the gatekeeper's tier, else the enemies'.</summary>
        public int ThreatTier(ShipCatalog catalog) =>
            IsGate && GatekeeperShip != null && catalog.Get(GatekeeperShip) is ShipDefinition g ? g.Tier : EnemyTier;
    }

    /// <summary>Why an edge could not be crossed, for the HUD.</summary>
    public enum CrossResult { Ok, WorldEdge, LockedIn, VeilNeedsEnergy, VeilOnlyGates }

    /// <summary>A radiation icon (spec 7): a sector above the player's tier within three sectors.</summary>
    public struct Radiation
    {
        public SectorCoord Coord;
        public int Gap;
        public Element Light;
    }

    /// <summary>
    /// The world (spec 7, M2 scale): a 5 x 5 grid in layers around a safe origin.
    /// Two rival AIs own contiguous halves; one veil lies between layers 1 and 2
    /// and the only way through it is a gate, a lock-in sector held by a rival
    /// boss. Rival borders drift between lives; player territory never does.
    /// </summary>
    public sealed class WorldGrid
    {
        public const int Radius = 2;                       // coordinates -2..2
        public readonly Dictionary<SectorCoord, Sector> Sectors = new Dictionary<SectorCoord, Sector>();
        /// <summary>Energy needed to cross the boundary from layer n to n+1 (index n). Layer 0 to 1 is open.</summary>
        public float[] VeilThreshold = { 0f, 300f };
        public static readonly SectorCoord Origin = new SectorCoord(0, 0);

        public Sector this[SectorCoord c] => Sectors.TryGetValue(c, out Sector s) ? s : null;
        public bool Contains(SectorCoord c) => Sectors.ContainsKey(c);
        public IEnumerable<Sector> All => Sectors.Values;

        /// <summary>Build the M2 world. Fixed layout; only border drift (between lives) varies it.</summary>
        public static WorldGrid Build(Tuning t)
        {
            var w = new WorldGrid { VeilThreshold = (float[])t.VeilThresholds.Clone() };
            for (int y = -Radius; y <= Radius; y++)
                for (int x = -Radius; x <= Radius; x++)
                {
                    var c = new SectorCoord(x, y);
                    var s = new Sector { Coord = c };
                    if (c.Layer == 0)
                    {
                        s.Owner = Element.None;
                        s.EnemyTier = 0;
                        s.EnemyCount = 0;
                    }
                    else
                    {
                        // Fire holds the east, corruption the west; the middle column splits north/south.
                        s.Owner = x > 0 || (x == 0 && y < 0) ? Element.Fire : Element.Corruption;
                        s.EnemyTier = c.Layer;             // layer 1: tier 1, layer 2: tier 2
                        s.EnemyCount = t.SectorEnemyBase + t.SectorEnemyPerLayer * c.Layer;
                    }
                    w.Sectors[c] = s;
                }
            // The gate: on the fire side, east of the origin, held by a fire tier-3 rival.
            Sector gate = w[new SectorCoord(2, 0)];
            gate.IsGate = true;
            gate.GatekeeperShip = "fire_t3_scorch";
            gate.EnemyCount = 0;
            return w;
        }

        public float ThresholdToEnter(SectorCoord to)
        {
            int layer = to.Layer;
            return layer >= 1 && layer - 1 < VeilThreshold.Length ? VeilThreshold[layer - 1] : 0f;
        }

        /// <summary>
        /// Spec 7: crossing outward over a veil needs energy at or above its threshold, and
        /// the only way through is a gate. Inward and sideways moves are free. A gate being
        /// fought locks every exit until its gatekeeper is beaten.
        /// </summary>
        public CrossResult CanCross(SectorCoord from, SectorCoord to, float energy, bool lockedIn, Meta meta)
        {
            if (!Contains(to)) return CrossResult.WorldEdge;
            if (lockedIn) return CrossResult.LockedIn;
            if (to.Layer > from.Layer)
            {
                float threshold = ThresholdToEnter(to);
                if (threshold > 0f)
                {
                    if (!this[to].IsGate) return CrossResult.VeilOnlyGates;
                    if (energy < threshold) return CrossResult.VeilNeedsEnergy;
                }
            }
            return CrossResult.Ok;
        }

        /// <summary>Spec 7: teleport to a checkpoint needs energy at or above that layer's veil threshold.</summary>
        public bool CanTeleport(SectorCoord to, float energy, Meta meta) =>
            meta.Checkpoints.Contains(to) && energy >= ThresholdToEnter(to);

        /// <summary>Spec 7: sectors within 3 of the player whose threat is above the player's tier show a radiation icon.</summary>
        public List<Radiation> RadiationNear(SectorCoord at, int playerTier, ShipCatalog catalog, Meta meta)
        {
            var list = new List<Radiation>();
            foreach (Sector s in Sectors.Values)
            {
                if (SectorCoord.Distance(s.Coord, at) > 3 || meta.PlayerTerritory.Contains(s.Coord)) continue;
                if (s.IsGate && meta.BeatenGates.Contains(s.Coord)) continue;
                int threat = s.ThreatTier(catalog);
                if (threat > playerTier) list.Add(new Radiation { Coord = s.Coord, Gap = threat - playerTier, Light = s.Owner });
            }
            list.Sort((a, b) => a.Coord.Y != b.Coord.Y ? a.Coord.Y.CompareTo(b.Coord.Y) : a.Coord.X.CompareTo(b.Coord.X));
            return list;
        }

        /// <summary>
        /// Spec 7: rivals fight each other off-screen, so between lives a rival sector on the
        /// border may change hands. Player territory, gates and the origin never do, and a flip
        /// that would split the losing rival's region in two is not taken (each rival owns a
        /// contiguous region). Returns the sectors that changed hands.
        /// </summary>
        public List<SectorCoord> DriftBorders(DeterministicRandom rng, Meta meta, int flips)
        {
            var changed = new List<SectorCoord>();
            for (int i = 0; i < flips; i++)
            {
                var candidates = new List<(Sector s, Element to)>();
                foreach (Sector s in SortedSectors())
                {
                    // Each sector changes hands at most once a death (no flip-and-flip-back).
                    if (s.Layer == 0 || s.IsGate || meta.PlayerTerritory.Contains(s.Coord) || changed.Contains(s.Coord)) continue;
                    foreach (Edge e in Edges.All)
                    {
                        // Take the neighbour's colours: the rival next door won that fight. A sector the
                        // player holds is nobody's rival land, so it cannot be the winner next door.
                        if (!(this[s.Coord.Step(e)] is Sector n) || !IsRivalLand(n, meta) || n.Owner == s.Owner) continue;
                        if (StaysContiguousWithout(s, meta)) candidates.Add((s, n.Owner));
                        break;
                    }
                }
                if (candidates.Count == 0) break;
                var pick = candidates[rng.RangeInt(0, candidates.Count)];
                pick.s.Owner = pick.to;
                changed.Add(pick.s.Coord);
            }
            return changed;
        }

        /// <summary>A sector a rival actually holds: not the origin, not the player's territory.</summary>
        public static bool IsRivalLand(Sector s, Meta meta) =>
            s.Layer > 0 && s.Owner != Element.None && !meta.PlayerTerritory.Contains(s.Coord);

        /// <summary>
        /// True when the sector's owner still holds one connected piece of rival land without it
        /// (4-neighbour; the origin and player territory belong to no rival), and still holds something.
        /// </summary>
        public bool StaysContiguousWithout(Sector gone, Meta meta)
        {
            var rest = new List<SectorCoord>();
            foreach (Sector s in Sectors.Values)
                if (s != gone && IsRivalLand(s, meta) && s.Owner == gone.Owner) rest.Add(s.Coord);
            if (rest.Count == 0) return false;   // never erase a rival
            return CountConnected(rest[0], c => c != gone.Coord && this[c] is Sector x && IsRivalLand(x, meta) && x.Owner == gone.Owner) == rest.Count;
        }

        /// <summary>Is every rival's land one connected piece? (What drift must never break.)</summary>
        public bool RegionsContiguous(Meta meta)
        {
            foreach (Element e in new[] { Element.Fire, Element.Lightning, Element.Void, Element.Corruption })
            {
                var cells = new List<SectorCoord>();
                foreach (Sector s in Sectors.Values) if (IsRivalLand(s, meta) && s.Owner == e) cells.Add(s.Coord);
                if (cells.Count == 0) continue;
                if (CountConnected(cells[0], c => this[c] is Sector x && IsRivalLand(x, meta) && x.Owner == e) != cells.Count) return false;
            }
            return true;
        }

        private int CountConnected(SectorCoord start, Func<SectorCoord, bool> member)
        {
            var seen = new HashSet<SectorCoord> { start };
            var queue = new Queue<SectorCoord>();
            queue.Enqueue(start);
            while (queue.Count > 0)
            {
                SectorCoord c = queue.Dequeue();
                foreach (Edge e in Edges.All)
                {
                    SectorCoord n = c.Step(e);
                    if (Contains(n) && member(n) && seen.Add(n)) queue.Enqueue(n);
                }
            }
            return seen.Count;
        }

        /// <summary>Row-major order, so every loop over sectors is deterministic whatever the dictionary does.</summary>
        public List<Sector> SortedSectors()
        {
            var list = new List<Sector>(Sectors.Values);
            list.Sort((a, b) => a.Coord.Y != b.Coord.Y ? a.Coord.Y.CompareTo(b.Coord.Y) : a.Coord.X.CompareTo(b.Coord.X));
            return list;
        }

        /// <summary>
        /// Shortest route of legal crossings from one sector to another at the given energy
        /// (breadth-first, edges tried N, E, S, W). Empty when unreachable or already there.
        /// Used by the world bot; the map shows the same rules.
        /// </summary>
        public List<SectorCoord> Route(SectorCoord from, SectorCoord to, float energy, Meta meta)
        {
            var prev = new Dictionary<SectorCoord, SectorCoord>();
            var queue = new Queue<SectorCoord>();
            var seen = new HashSet<SectorCoord> { from };
            queue.Enqueue(from);
            while (queue.Count > 0)
            {
                SectorCoord c = queue.Dequeue();
                if (c == to) break;
                foreach (Edge e in Edges.All)
                {
                    SectorCoord n = c.Step(e);
                    if (seen.Contains(n) || CanCross(c, n, energy, false, meta) != CrossResult.Ok) continue;
                    seen.Add(n);
                    prev[n] = c;
                    queue.Enqueue(n);
                }
            }
            var path = new List<SectorCoord>();
            if (from == to || !prev.ContainsKey(to)) return path;
            for (SectorCoord c = to; c != from; c = prev[c]) path.Add(c);
            path.Reverse();
            return path;
        }

        /// <summary>The edge of `from` that leads to the adjacent sector `to`.</summary>
        public static Edge EdgeToward(SectorCoord from, SectorCoord to) =>
            to.X > from.X ? Edge.East : to.X < from.X ? Edge.West : to.Y < from.Y ? Edge.North : Edge.South;
    }
}
