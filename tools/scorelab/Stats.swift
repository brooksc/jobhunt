import Foundation

enum Stats {
    static func median(_ v: [Int]) -> Int {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[s.count / 2]
    }

    static func pct(_ v: [Int], _ predicate: (Int) -> Bool) -> Double {
        v.isEmpty ? 0 : 100 * Double(v.count(where: predicate)) / Double(v.count)
    }

    /// Distinct score values among the highest `n`, as a percentage of `n`.
    ///
    /// This is the metric that matters for the way the list is used: the user ranks the top and picks
    /// what to spend an evening on, so resolution *there* decides whether the score is doing any work.
    /// A whole-corpus tie rate is useless for comparing variants — with hundreds of jobs over ~100
    /// possible values it sits at 97%+ for everything.
    static func topResolution(_ v: [Int], n: Int = 30) -> Double {
        guard !v.isEmpty else { return 0 }
        let top = v.sorted(by: >).prefix(n)
        return 100 * Double(Set(top).count) / Double(top.count)
    }

    static func sd(_ v: [Int]) -> Double {
        guard v.count > 1 else { return 0 }
        let mean = Double(v.reduce(0, +)) / Double(v.count)
        return (v.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(v.count)).squareRoot()
    }

    /// Rank correlation against the baseline: how much a variant reshuffles the list the user works
    /// down. A variant can improve every distribution statistic and still be wrong if it reorders.
    static func spearman(_ a: [Int], _ b: [Int]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 1 }
        func ranks(_ v: [Int]) -> [Double] {
            let order = v.indices.sorted { v[$0] < v[$1] }
            var r = [Double](repeating: 0, count: v.count)
            for (pos, idx) in order.enumerated() { r[idx] = Double(pos) }
            return r
        }
        let ra = ranks(a), rb = ranks(b)
        let n = Double(a.count)
        let d2 = zip(ra, rb).reduce(0.0) { $0 + pow($1.0 - $1.1, 2) }
        return 1 - 6 * d2 / (n * (n * n - 1))
    }

    /// Mean absolute error against a target ranking's scores.
    static func mae(_ a: [Int], _ b: [Int]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        return zip(a, b).reduce(0.0) { $0 + Double(abs($1.0 - $1.1)) } / Double(a.count)
    }

    /// How many of the target's best `n` also appear in the candidate's best `n`.
    ///
    /// The user triages from the top of the list, so this is the criterion that decides whether a
    /// change is worth shipping — a variant can improve MAE across the corpus while still failing to
    /// put the right jobs first.
    static func topOverlap(_ candidate: [Int], _ target: [Int], n: Int) -> Int {
        func best(_ v: [Int]) -> Set<Int> {
            Set(v.indices.sorted { v[$0] > v[$1] }.prefix(n))
        }
        return best(candidate).intersection(best(target)).count
    }
}
