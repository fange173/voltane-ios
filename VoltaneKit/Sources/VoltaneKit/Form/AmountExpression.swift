import Foundation

/// 金额输入框里的简单算式，例如「200+15」。支持 + - * / ( ) 和小数，`×`、`÷` 与 `*`、`/` 等价，用 Decimal 计算。
public enum AmountExpression {
    public static func evaluate(_ text: String) -> Decimal? {
        var t = text.filter { !"，, \t\n¥".contains($0) }
        t = t.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        guard !t.isEmpty, t.allSatisfy({ "0123456789.+-*/()".contains($0) }) else { return nil }
        var parser = Parser(chars: Array(t))
        guard let v = try? parser.expression(), parser.index == parser.chars.count else { return nil }
        return v
    }

    /// 解析成整数分，四舍五入；解析失败返回 nil。
    public static func cents(_ text: String) -> Int? { evaluate(text)?.cents }

    private struct Failure: Error {}

    private struct Parser {
        let chars: [Character]
        var index = 0

        init(chars: [Character]) { self.chars = chars }

        func peek() -> Character? { index < chars.count ? chars[index] : nil }

        mutating func number() throws -> Decimal {
            if peek() == "(" {
                index += 1
                let v = try expression()
                guard peek() == ")" else { throw Failure() }
                index += 1
                return v
            }
            if peek() == "-" {
                index += 1
                return -(try number())
            }
            var digits = ""
            while let c = peek(), c.isASCII, c.isNumber { digits.append(c); index += 1 }
            if peek() == ".", index + 1 < chars.count, chars[index + 1].isASCII, chars[index + 1].isNumber {
                digits.append(".")
                index += 1
                while let c = peek(), c.isASCII, c.isNumber { digits.append(c); index += 1 }
            }
            guard !digits.isEmpty, let v = Decimal(plain: digits) else { throw Failure() }
            return v
        }

        mutating func term() throws -> Decimal {
            var v = try number()
            while let c = peek(), c == "*" || c == "/" {
                index += 1
                let rhs = try number()
                if c == "*" { v *= rhs } else {
                    guard rhs != 0 else { throw Failure() }
                    v /= rhs
                }
            }
            return v
        }

        mutating func expression() throws -> Decimal {
            var v = try term()
            while let c = peek(), c == "+" || c == "-" {
                index += 1
                let rhs = try term()
                v = c == "+" ? v + rhs : v - rhs
            }
            return v
        }
    }
}
