import Foundation

/// Why an app is closed.
public enum BlockReason: String, Codable, Equatable {
    case minecraftOver = "minecraft_over"
    case studio
}

public enum Blocking {
    /// Usage key of Minecraft (the agent reports Minecraft Java under this bundle id).
    public static let minecraftKey = "app:com.mojang.minecraft"
    /// Categories closed during a study window.
    public static let studioBlocked: Set<UsageCategory> = [.games, .coding]

    public static func reason(appKey: String, category: UsageCategory?,
                              minecraftRemaining: Int?, inStudio: Bool) -> BlockReason? {
        if UsageLog.isSite(appKey) || UsageLog.isBrowser(appKey) {
            return nil
        }
        if inStudio && (appKey == minecraftKey || (category != nil && studioBlocked.contains(category!))) {
            return .studio
        }
        if appKey == minecraftKey && minecraftRemaining == 0 {
            return .minecraftOver
        }
        return nil
    }
}
