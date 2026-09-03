import OSLog

enum Log {
    private static let subsystem = "com.example.ScoreStand"

    static let library = Logger(subsystem: subsystem, category: "library")
    static let rendering = Logger(subsystem: subsystem, category: "rendering")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let performance = Logger(subsystem: subsystem, category: "performance")
    static let purchase = Logger(subsystem: subsystem, category: "purchase")
    static let backup = Logger(subsystem: subsystem, category: "backup")
}
