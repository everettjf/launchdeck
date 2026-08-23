import Foundation
import LaunchDeckCore

enum UtilitySearchProvider {
    private static let emoji: [(String, [String])] = [
        ("😀", ["smile", "happy", "face"]), ("😂", ["laugh", "tears", "funny"]),
        ("❤️", ["heart", "love"]), ("👍", ["thumb", "like", "yes"]),
        ("🎉", ["party", "celebrate"]), ("🔥", ["fire", "hot"]),
        ("✅", ["check", "done", "yes"]), ("🚀", ["rocket", "launch"]),
        ("💡", ["idea", "light"]), ("⚠️", ["warning", "alert"]),
    ]

    static func results(for rawQuery: String, quicklinks: [Quicklink] = QuicklinkStore.builtIns) -> [SearchItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [SearchItem] = []
        if let value = ArithmeticEvaluator.evaluate(query) {
            let formatted = value.formatted(.number.precision(.fractionLength(0...8)))
            results.append(.init(id: "calculation:\(query)", kind: .calculation, title: formatted,
                                 subtitle: query, keywords: ["calculator", "result"], target: .copyText(formatted)))
        }
        if let conversion = UnitConversion.convert(query) {
            results.append(.init(id: "conversion:\(query)", kind: .calculation,
                                 title: conversion.result, subtitle: conversion.description,
                                 keywords: ["convert", "unit"], target: .copyText(conversion.result)))
        }
        let lower = query.lowercased()
        results += emoji.compactMap { symbol, keywords in
            guard symbol.contains(query) || keywords.contains(where: { $0.contains(lower) }) else { return nil }
            return .init(id: "emoji:\(symbol)", kind: .emoji, title: symbol,
                         subtitle: keywords.joined(separator: ", "), keywords: keywords, target: .copyText(symbol))
        }
        if let split = query.firstIndex(of: " ") {
            let prefix = String(query[..<split]).lowercased()
            let term = String(query[query.index(after: split)...])
            if let quicklink = quicklinks.first(where: { $0.keyword.lowercased() == prefix }),
               let url = quicklink.url(for: term) {
                results.append(.init(id: "quicklink:\(prefix):\(term)", kind: .quicklink,
                                     title: "\(quicklink.name): \(term)", subtitle: url.host,
                                     keywords: ["web", "quicklink"], target: .url(url)))
            }
        }
        return results
    }
}

private enum UnitConversion {
    private static let factors: [String: (dimension: String, base: Double)] = [
        "mm": ("length", 0.001), "cm": ("length", 0.01), "m": ("length", 1), "km": ("length", 1000),
        "in": ("length", 0.0254), "ft": ("length", 0.3048), "yd": ("length", 0.9144), "mi": ("length", 1609.344),
        "mg": ("mass", 0.001), "g": ("mass", 1), "kg": ("mass", 1000), "oz": ("mass", 28.349523125), "lb": ("mass", 453.59237),
    ]

    static func convert(_ input: String) -> (result: String, description: String)? {
        let pattern = #"^\s*(-?[0-9]+(?:\.[0-9]+)?)\s*([A-Za-z°]+)\s+(?:to|in)\s+([A-Za-z°]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let valueRange = Range(match.range(at: 1), in: input),
              let fromRange = Range(match.range(at: 2), in: input),
              let toRange = Range(match.range(at: 3), in: input),
              let value = Double(input[valueRange]) else { return nil }
        let from = input[fromRange].lowercased().replacingOccurrences(of: "°", with: "")
        let to = input[toRange].lowercased().replacingOccurrences(of: "°", with: "")
        let converted: Double
        if ["c", "f", "k"].contains(from), ["c", "f", "k"].contains(to) {
            let celsius = from == "c" ? value : (from == "f" ? (value - 32) * 5 / 9 : value - 273.15)
            converted = to == "c" ? celsius : (to == "f" ? celsius * 9 / 5 + 32 : celsius + 273.15)
        } else {
            guard let source = factors[from], let destination = factors[to], source.dimension == destination.dimension else { return nil }
            converted = value * source.base / destination.base
        }
        let formatted = converted.formatted(.number.precision(.fractionLength(0...6)))
        return ("\(formatted) \(to)", "\(value.formatted()) \(from) to \(to)")
    }
}

private enum ArithmeticEvaluator {
    static func evaluate(_ input: String) -> Double? {
        guard input.range(of: #"^[0-9+\-*/().\s]+$"#, options: .regularExpression) != nil,
              input.contains(where: "+-*/".contains) else { return nil }
        var parser = Parser(characters: Array(input.filter { !$0.isWhitespace }))
        guard let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var isAtEnd: Bool { index == characters.count }
        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while index < characters.count, characters[index] == "+" || characters[index] == "-" {
                let operation = characters[index]; index += 1
                guard let rhs = term() else { return nil }
                value = operation == "+" ? value + rhs : value - rhs
            }
            return value
        }
        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while index < characters.count, characters[index] == "*" || characters[index] == "/" {
                let operation = characters[index]; index += 1
                guard let rhs = factor(), operation != "/" || rhs != 0 else { return nil }
                value = operation == "*" ? value * rhs : value / rhs
            }
            return value
        }
        mutating func factor() -> Double? {
            if index < characters.count, characters[index] == "(" {
                index += 1
                guard let value = expression(), index < characters.count, characters[index] == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            if index < characters.count, characters[index] == "-" { index += 1 }
            while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }
    }
}
