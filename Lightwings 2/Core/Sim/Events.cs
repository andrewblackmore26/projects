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
    }

    /// <summary>
    /// Something the view may want to show. Each event keeps its tick so the
    /// view can honour the 0.25 s minimum visible lifetime (spec 9).
    /// </summary>
    public struct GameEvent
    {
        /// <summary>Monotonic across runs: arena ticks restart at death, this never does.</summary>
        public long Seq;
        public EventKind Kind;
        public long Tick;
        public Vec2 Pos;
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
        private readonly int[] _counts = new int[16];
        private readonly long[] _firstTick = new long[16];
        public long Total { get; private set; }

        public EventLog()
        {
            for (int i = 0; i < _firstTick.Length; i++) _firstTick[i] = -1;
        }

        public void Add(EventKind kind, long tick, Vec2 pos, Element element = Element.None, float value = 0f, int shipId = -1)
        {
            _ring[_next] = new GameEvent { Seq = Total, Kind = kind, Tick = tick, Pos = pos, Element = element, Value = value, ShipId = shipId };
            _next = (_next + 1) % Capacity;
            _counts[(int)kind]++;
            if (_firstTick[(int)kind] < 0) _firstTick[(int)kind] = tick;
            Total++;
        }

        public int Count(EventKind kind) => _counts[(int)kind];
        public long FirstTick(EventKind kind) => _firstTick[(int)kind];

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
