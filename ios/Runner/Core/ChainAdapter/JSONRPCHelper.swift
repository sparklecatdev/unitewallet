import Foundation

// MARK: - JSON RPC Request / Response Types

struct CoreJSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: [CoreAnyEncodable]

    init(method: String, params: [CoreAnyEncodable] = []) {
        self.id = String(Int(Date().timeIntervalSince1970 * 1000) % 100000)
        self.method = method
        self.params = params
    }
}

struct CoreAnyEncodable: Encodable {
    let value: EncodableValue

    init(_ value: String) { self.value = .string(value) }
    init(_ value: [String: String]) { self.value = .stringDict(value) }
    init(_ value: [String: CoreAnyEncodable]) { self.value = .encodableDict(value) }
    init(_ value: Int) { self.value = .int(value) }
    init(_ value: Bool) { self.value = .bool(value) }

    enum EncodableValue {
        case string(String)
        case stringDict([String: String])
        case encodableDict([String: CoreAnyEncodable])
        case int(Int)
        case bool(Bool)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .string(let s): try container.encode(s)
        case .stringDict(let d): try container.encode(d)
        case .encodableDict(let d): try container.encode(d)
        case .int(let i): try container.encode(i)
        case .bool(let b): try container.encode(b)
        }
    }
}

struct CoreEthereumBalanceResponse: Decodable {
    let result: String
}

struct CoreSolanaBalanceResponse: Decodable {
    let result: CoreSolanaBalanceResult
}

struct CoreSolanaBalanceResult: Decodable {
    let value: Int64
}

// MARK: - RPC Helper

enum JSONRPCHelper {
    static func post<Response: Decodable>(
        _ request: CoreJSONRPCRequest,
        url: URL,
        responseType: Response.Type
    ) async throws -> Response {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TransactionServiceError.rpcError("HTTP error from \(url.host ?? "unknown")")
        }
        return try decode(data, as: Response.self)
    }

    static func get<Response: Decodable>(
        url: URL,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TransactionServiceError.rpcError("HTTP error from \(url.host ?? "unknown")")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func decode<Response: Decodable>(_ data: Data, as type: Response.Type) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            if let rpcError = try? JSONDecoder().decode(CoreJSONRPCErrorResponse.self, from: data) {
                throw TransactionServiceError.rpcError("RPC error \(rpcError.error.code): \(rpcError.error.message)")
            }
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransactionServiceError.rpcError(raw?.isEmpty == false ? raw! : "Unexpected RPC response.")
        }
    }
}

struct CoreJSONRPCErrorResponse: Decodable {
    let error: CoreJSONRPCErrorPayload
}

struct CoreJSONRPCErrorPayload: Decodable {
    let code: Int
    let message: String
}

// MARK: - Helpers

func pow10(_ power: Int) -> Decimal {
    Decimal(sign: .plus, exponent: power, significand: 1)
}

extension Decimal {
    func smallestUnit(decimals: Int) throws -> Int64 {
        guard self > 0 else { throw TransactionServiceError.invalidAmount }
        let scaled = self * pow10(decimals)
        let rounded = NSDecimalNumber(decimal: scaled).rounding(accordingToBehavior: nil)
        return rounded.int64Value
    }
}

extension Data {
    static func hexUInt64(_ value: UInt64) -> Data {
        value == 0 ? Data() : Data(hexString: String(value, radix: 16).leftPaddedToEvenLength) ?? Data()
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    func reversedData() -> Data {
        Data(reversed())
    }
}

extension String {
    var stripHexPrefix: String {
        hasPrefix("0x") ? String(dropFirst(2)) : self
    }

    var prefixed0x: String {
        hasPrefix("0x") ? self : "0x\(self)"
    }

    func leftPadded(to count: Int) -> String {
        if self.count >= count { return self }
        return String(repeating: "0", count: count - self.count) + self
    }

    var leftPaddedToEvenLength: String {
        count.isMultiple(of: 2) ? self : "0\(self)"
    }
}

extension Decimal {
    static func fromHexString(_ hex: String) -> Decimal {
        let clean = hex.stripHexPrefix
        guard !clean.isEmpty else { return 0 }
        let scanner = Scanner(string: clean)
        var bigInt: UInt64 = 0
        scanner.scanHexInt64(&bigInt)
        return Decimal(bigInt)
    }
}
