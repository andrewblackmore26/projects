using System;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// Light pickups (spec 6): hollow, slow-drifting versions of the element's
    /// base shape, each with its own running light. Struct-of-arrays like the
    /// bullets, for the same reasons.
    /// </summary>
    public sealed class PickupPool
    {
        public readonly int Capacity;
        public readonly float[] X, Y, VX, VY, DriftX, DriftY, Value;
        public readonly byte[] Elem, Size, PeriodIndex, PhaseIndex;
        public readonly int[] Ttl;
        public readonly long[] Born;
        public readonly bool[] Alive, Ambient;

        private readonly int[] _free;
        private int _freeCount;

        public int Live { get; private set; }
        public int LiveAmbient { get; private set; }
        public int High { get; private set; }

        public PickupPool(int capacity)
        {
            Capacity = capacity;
            X = new float[capacity]; Y = new float[capacity]; VX = new float[capacity]; VY = new float[capacity];
            DriftX = new float[capacity]; DriftY = new float[capacity]; Value = new float[capacity];
            Elem = new byte[capacity]; Size = new byte[capacity]; PeriodIndex = new byte[capacity]; PhaseIndex = new byte[capacity];
            Ttl = new int[capacity]; Born = new long[capacity]; Alive = new bool[capacity]; Ambient = new bool[capacity];
            _free = new int[capacity];
            Clear();
        }

        public void Clear()
        {
            Array.Clear(Alive, 0, Capacity);
            for (int i = 0; i < Capacity; i++) _free[i] = Capacity - 1 - i;
            _freeCount = Capacity;
            Live = 0;
            LiveAmbient = 0;
            High = 0;
        }

        public int Spawn(Element element, int size, float value, float x, float y, float driftX, float driftY,
            int periodIndex, int phaseIndex, int ttlTicks, long tick, bool ambient)
        {
            if (_freeCount == 0) return -1;
            int i = _free[--_freeCount];
            X[i] = x; Y[i] = y; VX[i] = driftX; VY[i] = driftY; DriftX[i] = driftX; DriftY[i] = driftY;
            Value[i] = value; Elem[i] = (byte)element; Size[i] = (byte)size;
            PeriodIndex[i] = (byte)periodIndex; PhaseIndex[i] = (byte)phaseIndex;
            Ttl[i] = ttlTicks; Born[i] = tick; Alive[i] = true; Ambient[i] = ambient;
            Live++;
            if (ambient) LiveAmbient++;
            if (i + 1 > High) High = i + 1;
            return i;
        }

        public void Free(int i)
        {
            if (!Alive[i]) return;
            Alive[i] = false;
            if (Ambient[i]) LiveAmbient--;
            _free[_freeCount++] = i;
            Live--;
        }
    }
}
