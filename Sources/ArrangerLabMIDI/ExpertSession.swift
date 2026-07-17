import ArrangerLabCore
import Foundation

public struct ExpertSession: Equatable, Sendable {
    public private(set) var connectedModel: String?
    public private(set) var isUnlocked = false

    public init() {}

    public mutating func unlock(typedModel: String, connectedModel: String) throws {
        guard typedModel.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(connectedModel) == .orderedSame else {
            throw ArrangerLabError.invalidValue("typed model does not match connected model")
        }
        self.connectedModel = connectedModel
        isUnlocked = true
    }

    public mutating func expire() { connectedModel = nil; isUnlocked = false }

    public func validateArbitrarySysEx(confirmed: Bool) throws {
        guard isUnlocked else { throw ArrangerLabError.expertModeRequired }
        guard confirmed else { throw ArrangerLabError.invalidValue("arbitrary SysEx requires an additional confirmation") }
    }
}
