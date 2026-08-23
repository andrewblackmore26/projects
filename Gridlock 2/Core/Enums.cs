namespace Gridlock.Core
{
    /// <summary>Who owns a node, beam, or contest side.</summary>
    public enum Owner
    {
        Neutral = 0,
        Player = 1,
        Ai = 2,
    }

    /// <summary>Node lifecycle (spec §4.2).</summary>
    public enum NodeState
    {
        Idle = 0,
        /// <summary>Being held (hold progress accumulating, visibly brightening).</summary>
        Overcharging = 1,
        /// <summary>Post-burst: no accrual, cannot send, capturable at frozen (usually zero) defense.</summary>
        Disabled = 2,
        /// <summary>Brief lock after capture; cannot send, still accrues.</summary>
        CaptureLocked = 3,
    }

    /// <summary>Match outcome. None = still in progress.</summary>
    public enum MatchResult
    {
        None = 0,
        PlayerWin = 1,
        AiWin = 2,
        /// <summary>Mutual annihilation.</summary>
        Draw = 3,
        /// <summary>Headless runner hit its wall-clock/sim-time cap (stall).</summary>
        Timeout = 4,
    }

    /// <summary>Level objective (spec §10.2).</summary>
    public enum ObjectiveType
    {
        /// <summary>Take all AI nodes (default).</summary>
        Eliminate = 0,
        /// <summary>Hold at least one node for N seconds.</summary>
        Survive = 1,
        /// <summary>Take specific node ids.</summary>
        Capture = 2,
        /// <summary>Eliminate using at most N sends (puzzle mode).</summary>
        Efficiency = 3,
    }
}
