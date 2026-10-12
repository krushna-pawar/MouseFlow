import Foundation

/// Verbose trace logging with the "[MouseFlow]" prefix. Compiled out of Release builds;
/// use NSLog directly for errors and lifecycle events that should always be logged.
func debugLog(_ format: String, _ args: CVarArg...) {
    #if DEBUG
    withVaList(args) { NSLogv("[MouseFlow] " + format, $0) }
    #endif
}
