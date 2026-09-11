using System;
using System.Collections.Generic;

namespace Lightship.Core.Sim
{
    /// <summary>
    /// Uniform grid over the arena, rebuilt from the live bullets every tick by
    /// counting sort: O(n) to build, O(cells touched) to query, no allocation
    /// after construction. Positions outside the arena clamp into the border
    /// cells, so nothing is ever lost.
    /// </summary>
    public sealed class SpatialHash
    {
        private readonly float _cell, _ox, _oy;
        private readonly int _cols, _rows;
        private readonly int[] _cellStart;   // cells + 1
        private readonly int[] _cursor;      // cells
        private readonly int[] _entries;     // capacity
        private readonly int[] _itemCell;    // capacity

        public int Cols => _cols;
        public int Rows => _rows;

        public SpatialHash(float width, float height, float cell, int capacity)
        {
            _cell = cell;
            _ox = -cell;
            _oy = -cell;
            _cols = (int)MathF.Ceiling(width / cell) + 2;
            _rows = (int)MathF.Ceiling(height / cell) + 2;
            _cellStart = new int[_cols * _rows + 1];
            _cursor = new int[_cols * _rows];
            _entries = new int[capacity];
            _itemCell = new int[capacity];
        }

        private int CellX(float x) => Math.Clamp((int)((x - _ox) / _cell), 0, _cols - 1);
        private int CellY(float y) => Math.Clamp((int)((y - _oy) / _cell), 0, _rows - 1);

        public void Rebuild(BulletPool b)
        {
            int cells = _cols * _rows;
            Array.Clear(_cursor, 0, cells);
            for (int i = 0; i < b.High; i++)
            {
                if (!b.Alive[i]) continue;
                int c = CellY(b.Y[i]) * _cols + CellX(b.X[i]);
                _itemCell[i] = c;
                _cursor[c]++;
            }
            _cellStart[0] = 0;
            for (int c = 0; c < cells; c++) _cellStart[c + 1] = _cellStart[c] + _cursor[c];
            Array.Copy(_cellStart, _cursor, cells);
            for (int i = 0; i < b.High; i++)
            {
                if (!b.Alive[i]) continue;
                _entries[_cursor[_itemCell[i]]++] = i;
            }
        }

        /// <summary>Every bullet index whose cell overlaps the circle; the caller does the precise test.</summary>
        public void Query(float x, float y, float r, List<int> into)
        {
            into.Clear();
            int x0 = CellX(x - r), x1 = CellX(x + r), y0 = CellY(y - r), y1 = CellY(y + r);
            for (int cy = y0; cy <= y1; cy++)
                for (int cx = x0; cx <= x1; cx++)
                {
                    int c = cy * _cols + cx;
                    for (int k = _cellStart[c]; k < _cellStart[c + 1]; k++) into.Add(_entries[k]);
                }
        }
    }
}
