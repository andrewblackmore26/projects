using System;
using Lightship.Core.Ships;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// Struct-of-arrays bullet storage with a free list: no allocation after
    /// construction, contiguous arrays for the renderer to pack from, and an
    /// index that never moves while a bullet lives (the spatial hash and the
    /// view both refer to bullets by index).
    /// </summary>
    public sealed class BulletPool
    {
        public readonly int Capacity;
        public readonly float[] X, Y, VX, VY, Radius, Damage;
        public readonly byte[] Owner, Elem, Shape;
        public readonly int[] Ttl;
        public readonly long[] Born;
        public readonly bool[] Alive;

        private readonly int[] _free;
        private int _freeCount;

        public int Live { get; private set; }
        /// <summary>One past the highest index ever used: the loop bound for iteration.</summary>
        public int High { get; private set; }

        public BulletPool(int capacity)
        {
            Capacity = capacity;
            X = new float[capacity]; Y = new float[capacity]; VX = new float[capacity]; VY = new float[capacity];
            Radius = new float[capacity]; Damage = new float[capacity];
            Owner = new byte[capacity]; Elem = new byte[capacity]; Shape = new byte[capacity];
            Ttl = new int[capacity]; Born = new long[capacity]; Alive = new bool[capacity];
            _free = new int[capacity];
            Clear();
        }

        public void Clear()
        {
            Array.Clear(Alive, 0, Capacity);
            for (int i = 0; i < Capacity; i++) _free[i] = Capacity - 1 - i;
            _freeCount = Capacity;
            Live = 0;
            High = 0;
        }

        public int Spawn(Faction owner, Element element, BulletShape shape, float x, float y, float vx, float vy,
            float radius, float damage, int ttlTicks, long tick)
        {
            if (_freeCount == 0) return -1;
            int i = _free[--_freeCount];
            X[i] = x; Y[i] = y; VX[i] = vx; VY[i] = vy;
            Radius[i] = radius; Damage[i] = damage;
            Owner[i] = (byte)owner; Elem[i] = (byte)element; Shape[i] = (byte)shape;
            Ttl[i] = ttlTicks; Born[i] = tick; Alive[i] = true;
            Live++;
            if (i + 1 > High) High = i + 1;
            return i;
        }

        public void Free(int i)
        {
            if (!Alive[i]) return;
            Alive[i] = false;
            _free[_freeCount++] = i;
            Live--;
        }
    }
}
