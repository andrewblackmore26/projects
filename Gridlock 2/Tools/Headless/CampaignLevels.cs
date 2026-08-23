using System.Collections.Generic;
using Gridlock.Core;
using Gridlock.Core.Levels;

namespace Gridlock.Headless
{
    /// <summary>
    /// Code-authored campaign levels (M7-lite). Authored with PathBuilder and
    /// exported to /Levels as JSON by `gen`; the JSON files are what ships — this
    /// code is the authoring source of truth until the in-engine editor (M6) exists.
    /// </summary>
    public static class CampaignLevels
    {
        public static IEnumerable<LevelData> All()
        {
            yield break; // filled in during content pass
        }
    }
}
