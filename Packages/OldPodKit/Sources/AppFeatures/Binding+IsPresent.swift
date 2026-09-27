import SwiftUI

extension Binding where Value: OptionalProtocol {
    /// `true` while the wrapped optional is non-nil; setting `false` clears it.
    /// Bridges an optional presentation state to a `Bool`-driven modifier.
    var isPresent: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.isSome },
            set: { if !$0 { wrappedValue = .absent } }
        )
    }
}

protocol OptionalProtocol {
    static var absent: Self { get }
    var isSome: Bool { get }
}

extension Optional: OptionalProtocol {
    static var absent: Self {
        nil
    }

    var isSome: Bool {
        self != nil
    }
}
