// SPDX-FileCopyrightText: 2026 BarutSRB
// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=upstream-derived; Upstream-Project=OmniWM; Upstream-Author=BarutSRB; Nehir-Changes-Since=2026; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

// NOTE: Swift 6.4's @TaskLocal macro concatenates @usableFromInline and
// nonisolated into an invalid attribute when expanding a global var. Declare
// the TaskLocal storage explicitly to avoid the macro bug while keeping the
// symbol usable from @inlinable code.
@usableFromInline
let appThreadToken: TaskLocal<AppThreadToken?> = TaskLocal(wrappedValue: nil)

@usableFromInline
struct AppThreadToken: Sendable, Equatable {
    @usableFromInline
    let pid: pid_t

    @inlinable
    init(pid: pid_t) {
        self.pid = pid
    }

    @usableFromInline
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid
    }

    @inlinable
    func checkEquals(_ other: AppThreadToken?) {
        precondition(self == other)
    }
}
