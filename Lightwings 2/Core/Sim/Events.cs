using System.Collections.Generic;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    public enum EventKind : byte
    {
        Hit,
        Kill,
        Absorb,
        Evolved,
        PlayerDamaged,
        PlayerDied,
        EnemySpawned,
        ReshapeStarted,
        ReshapeEnded,
        Infected,
        InfectSpread,
        DroneHatched,
        // World (spec 7). Pos of SectorEntered/Teleported is the arrival point, To the sector (x, y).
        SectorEntered,
        CrossBlocked,      // Value = (int)CrossResult, To = the sector that could not be entered
        GateWarning,       // the player is near an edge into an unbeaten gate; To = the gate
        GateLocked,
        GateBeaten,
        SectorCleared,     // Value = 1 when it newly became player territory
        Teleported,
        BorderShifted,     // Pos = the sector (x, y), Element = its new owner
        // Rivals (spec 8).
        RivalSpawned,
        RivalRetreat,
        RivalAbsorb,
        AimLine,           // a rival's aim line appeared; Value = ticks until it fires
    }

    /// <summary>
    /// Something the view may want to show. Each event keeps the arena tick it
    /// happened on so the view can honour the 0.25 s minimum visible lifetime
    /// (spec 9), and a sequence number. Arena ticks never restart within a game (a new
    /// sector or a new life carries the clock on), so ticks from different lives compare.
    /// </summary>
    public struct GameEvent
    {
        public long Seq;
        public EventKind Kind;
        public long Tick;
        public Vec2 Pos;
        public Vec2 To;          // a second point, for events with a direction (infection spread)
        public Element Element;
        public float Value;
        public int ShipId;
    }

    /// <summary>Ring buffer of recent events plus running counts for tests and the CLI.</summary>
    public sealed class EventLog
    {
        public const int Capacity = 256;
        private readonly GameEvent[] _ring = new GameEvent[Capacity];
        private int _next;
        private readonly int[] _counts = new int[32];
        public long Total { get; private set; }

        public void Add(EventKind kind, long tick, Vec2 pos, Element element = Element.None, float value = 0f, int shipId = -1, Vec2 to = default)
        {
            _ring[_next] = new GameEvent { Seq = Total, Kind = kind, Tick = tick, Pos = pos, To = to, Element = element, Value = value, ShipId = shipId };
            _next = (_next + 1) % Capacity;
            _counts[(int)kind]++;
            Total++;
        }

        public int Count(EventKind kind) => _counts[(int)kind];

        /// <summary>Events with Seq at or after the given sequence number still in the ring, oldest first.</summary>
        public void Since(long seq, List<GameEvent> into)
        {
            into.Clear();
            int n = (int)System.Math.Min(Total, Capacity);
            for (int k = n; k >= 1; k--)
            {
                GameEvent e = _ring[((_next - k) % Capacity + Capacity) % Capacity];
                if (e.Seq >= seq) into.Add(e);
            }
        }
    }
}
