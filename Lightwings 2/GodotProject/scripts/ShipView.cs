using Godot;
using Lightship.Core;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;

namespace Lightship.View
{
    /// <summary>
    /// One ship on screen: a single mesh rebuilt from Core geometry whenever
    /// the ship's shape or the camera zoom changes. Position, rotation and the
    /// breathing scale are plain Node2D transforms set by the arena view.
    /// </summary>
    public partial class ShipView : MeshInstance2D
    {
        private readonly ArrayMesh _mesh = new ArrayMesh();
        private readonly MeshData _data = new MeshData();

        public ShipGeometry Geometry { get; private set; }
        public ResolvedShip Resolved { get; private set; }
        public float BuiltZoom { get; private set; } = 1f;

        public ShipView()
        {
            Mesh = _mesh;
        }

        public void Rebuild(ResolvedShip ship, float zoom)
        {
            Resolved = ship;
            Geometry = ShipGeometry.Build(ship);
            ShipMeshBuilder.Build(Geometry, zoom, _data);
            ShipMeshFactory.Fill(_mesh, _data);
            BuiltZoom = zoom;
        }

        public void RebuildAtZoom(float zoom)
        {
            if (Resolved != null) Rebuild(Resolved, zoom);
        }

        /// <summary>Screen position of a ship-local point, honouring position, rotation and scale.</summary>
        public Vector2 ToScreen(Vec2 local) => ToGlobal(new Vector2(local.X, local.Y));
    }
}
