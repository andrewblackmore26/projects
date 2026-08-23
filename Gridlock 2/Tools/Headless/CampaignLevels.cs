using System.Collections.Generic;
using Gridlock.Core;
using Gridlock.Core.Levels;

namespace Gridlock.Headless
{
    /// <summary>
    /// Code-authored campaign levels (M7-lite). Exported to /Levels as JSON by
    /// `gen`; the JSON files are what ships — this code is the authoring source
    /// of truth until the in-engine editor (M6) exists.
    ///
    /// Design rules baked in from measurement (tasks/lessons.md):
    ///  - every home gets a hinterland (a backline node not bordering the enemy),
    ///    so there is somewhere safe to bank and send from;
    ///  - no neutral is wired to BOTH homes at distance 1 — that shape turns every
    ///    opening into a second-mover-wins race and compresses AI tiers;
    ///  - travel times are deliberately unequal (a long winding wire is
    ///    load-bearing, never "tidy" it);
    ///  - difficulty rises through board design first, AI tier second (§10.3).
    /// </summary>
    public static class CampaignLevels
    {
        public static IEnumerable<LevelData> All()
        {
            yield return Level01FirstLight();
            yield return Level02LongWayRound();
            yield return Level03Tollbooth();
            yield return Level04Switchback();
            yield return Level05Crossroads();
            yield return Level06Mirrorlock();
            yield return Level07Gauntlet();
        }

        /// <summary>Teach press-drag-release. Player out-earns a tier-1 opponent.</summary>
        private static LevelData Level01FirstLight()
        {
            var b = new BoardBuilder("level_01_first_light", "First Light", 1, parTime: 90f);
            int p = b.Node(-2, 0, "player");
            int backyard = b.Node(-3, 2, "neutral");
            int mid = b.Node(0, 0, "neutral");
            int a = b.Node(2, 0, "ai");
            b.Wire(p, backyard);
            b.Wire(p, mid);
            b.Wire(mid, a);
            return b.Level;
        }

        /// <summary>Visual distance lies: the "direct" wire to the hub winds far north; the stepping-stone route is faster.</summary>
        private static LevelData Level02LongWayRound()
        {
            var b = new BoardBuilder("level_02_long_way_round", "The Long Way Round", 2, parTime: 150f);
            int p = b.Node(-3, 0, "player");
            int stone = b.Node(-1, -2, "neutral");
            int hub = b.Node(0, 0, "neutral");
            int a = b.Node(3, 0, "ai");
            b.Wire(p, hub, -1, 7, 2, 8); // the lie: leaves toward the hub, wanders the north rim
            b.Wire(p, stone);
            b.Wire(stone, hub);
            b.Wire(a, hub);
            return b.Level;
        }

        /// <summary>A five-wire toll hub (defense 40) guards the middle: chipping over several sends is the lesson. Objective: capture it.</summary>
        private static LevelData Level03Tollbooth()
        {
            var b = new BoardBuilder("level_03_tollbooth", "Tollbooth", 3, parTime: 240f);
            int p = b.Node(-4, 0, "player");
            int a = b.Node(4, 0, "ai");
            int toll = b.Node(0, 0, "neutral");
            int nw = b.Node(-1, -2, "neutral");
            int se = b.Node(1, 2, "neutral");
            b.Wire(p, toll);
            b.Wire(a, toll);
            b.Wire(nw, toll);
            b.Wire(se, toll);
            b.Wire(p, nw);
            b.Wire(a, se);
            b.Level.Objective = ObjectiveType.Capture;
            b.Level.ObjectiveNodeIds.Add(toll);
            return b.Level;
        }

        /// <summary>Spec §10.1's named board: every wire switchbacks, so reading the board wrong loses races. Burst tier arrives (4).</summary>
        private static LevelData Level04Switchback()
        {
            var b = new BoardBuilder("level_04_switchback", "Switchback", 4, parTime: 240f);
            int p = b.Node(-4, 1, "player");
            int bp = b.Node(-6, 3, "neutral");
            int n1 = b.Node(-1, 1, "neutral");
            int n2 = b.Node(1, -1, "neutral");
            int a = b.Node(4, -1, "ai");
            int ba = b.Node(6, -3, "neutral");
            b.Wire(p, bp);
            b.Wire(a, ba);
            b.Wire(p, n1, -5, -5);   // south switchback
            b.Wire(n1, n2, 1, 7);    // north switchback
            b.Wire(n2, a, 5, -7);    // south again
            // Backline links raise the staging nodes to degree 3 (cap 36): a full
            // stage can crack a full home (cap 24) — without these the endgame
            // measured as a 25% stall grind.
            b.Wire(n1, bp);
            b.Wire(n2, ba);
            return b.Level;
        }

        /// <summary>Two corridors crossing at a degree-4 centre; holding the cross is the game.</summary>
        private static LevelData Level05Crossroads()
        {
            var b = new BoardBuilder("level_05_crossroads", "Crossroads", 5, parTime: 300f);
            int p = b.Node(-5, 0, "player");
            int bp = b.Node(-7, 1, "neutral");
            int a = b.Node(5, 0, "ai");
            int ba = b.Node(7, -1, "neutral");
            int c = b.Node(0, 0, "neutral");
            int nw = b.Node(-2, -2, "neutral");
            int sw = b.Node(-3, 3, "neutral");
            int ne = b.Node(3, -3, "neutral");
            int se = b.Node(2, 2, "neutral");
            b.Wire(p, bp);
            b.Wire(a, ba);
            b.Wire(p, nw);
            b.Wire(p, sw);
            b.Wire(a, ne);
            b.Wire(a, se);
            b.Wire(nw, c);
            b.Wire(sw, c);
            b.Wire(ne, c);
            b.Wire(se, c);
            // Homes are deliberately uncrackable from the cap-24 satellites —
            // the win is CONTROL, not elimination: hold the cross and both far
            // satellites simultaneously. (A degree-6 centre with direct home
            // corridors was tried and abandoned: six face-edge arrivals around
            // one hub exhaust the corner radials and the router cannot land the
            // last spokes.)
            b.Level.Objective = ObjectiveType.Capture;
            b.Level.ObjectiveNodeIds.Add(c);
            b.Level.ObjectiveNodeIds.Add(ne);
            b.Level.ObjectiveNodeIds.Add(se);
            return b.Level;
        }

        /// <summary>
        /// The fairness board: exactly point-symmetric (mirrored paths, not
        /// re-routed), two-hop buffers in front of both homes, and a long winding
        /// flank pair breaking simultaneous arrivals. Balance gates run here.
        /// </summary>
        private static LevelData Level06Mirrorlock()
        {
            var b = new BoardBuilder("level_06_mirrorlock", "Mirrorlock", 6, parTime: 300f);
            int p = b.Node(-6, 0, "player");
            int a = b.Node(6, 0, "ai");
            int bp = b.Node(-8, 2, "neutral");
            int ba = b.Node(8, -2, "neutral");
            int c = b.Node(0, 0, "neutral");
            int mp = b.Node(-3, -1, "neutral");
            int ma = b.Node(3, 1, "neutral");
            int fp = b.Node(-2, 3, "neutral");
            int fa = b.Node(2, -3, "neutral");

            int wBack = b.Wire(p, bp);
            b.MirrorWire(wBack, a, ba);
            int wMid = b.Wire(p, mp);
            b.MirrorWire(wMid, a, ma);
            int wMidC = b.Wire(mp, c);
            b.MirrorWire(wMidC, ma, c);
            int wFlank = b.Wire(p, fp, -8, 8); // long southern flank, winds before turning in
            b.MirrorWire(wFlank, a, fa);
            int wFlankC = b.Wire(fp, c);
            b.MirrorWire(wFlankC, fa, c);
            return b.Level;
        }

        /// <summary>Survive: outnumbered against a tier-7 economy — hold any node for 90 seconds.</summary>
        private static LevelData Level07Gauntlet()
        {
            var b = new BoardBuilder("level_07_gauntlet", "Gauntlet", 7, parTime: 90f);
            int p = b.Node(-5, 1, "player", charge: 20f);
            int bp = b.Node(-7, 2, "neutral");
            int bp2 = b.Node(-6, -1, "neutral");
            int mid = b.Node(-2, 0, "neutral");
            int a1 = b.Node(2, 0, "ai");
            int a2 = b.Node(4, -2, "ai");
            int a3 = b.Node(3, 2, "ai");
            b.Wire(p, bp);
            b.Wire(p, bp2);
            b.Wire(p, mid);
            b.Wire(mid, a1, 0, -8); // the assault road is LONG: the player sees it coming
            b.Wire(a1, a2);
            b.Wire(a1, a3);
            b.Wire(a3, mid, 0, 8);
            b.Level.Objective = ObjectiveType.Survive;
            b.Level.ObjectiveSeconds = 90f;
            return b.Level;
        }
    }
}
