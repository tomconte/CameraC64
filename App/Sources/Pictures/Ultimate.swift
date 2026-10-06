import Foundation

/// An Ultimate 64, C64 Ultimate or Ultimate-II+ on the network, where Send to
/// C64 runs a picture's program (plan, section 9), through the Ultimate's
/// REST API (1541u-documentation.readthedocs.io, "REST API Calls").
///
/// The program goes, as it is, in the body of `POST /v1/runners:run_prg`:
/// the Ultimate resets the C64, puts the program in its memory and runs it.
/// Since firmware 3.12, an Ultimate can have a network password, which goes
/// in an `X-Password` header. The API is plain HTTP, which App/Info.plist
/// allows on the local network only.
nonisolated struct Ultimate: Sendable {
    /// Why a picture did not get to the C64.
    nonisolated enum Failure: Error, Equatable {
        /// The address in Settings is not one.
        case badAddress
        /// The address is a name outside the local network, where the app
        /// only uses HTTPS, which the Ultimate does not offer.
        case notLocal
        /// The phone is on no network, or iOS keeps the app off the local
        /// network.
        case noNetwork
        /// Nothing answered at the address.
        case notFound
        /// The Ultimate has a password, and Settings has none, or another.
        case wrongPassword
        /// The Ultimate answered, but did not run the program, and why, if
        /// it said.
        case refused(String)

        /// What the TV says about it.
        var title: String {
            switch self {
            case .badAddress, .notLocal, .notFound: "C64 NOT FOUND"
            case .noNetwork: "NO NETWORK"
            case .wrongPassword: "WRONG PASSWORD"
            case .refused: "NOT SENT"
            }
        }

        var detail: String {
            switch self {
            case .badAddress, .notFound: "Check the Ultimate's address in Settings"
            case .notLocal: "Use the Ultimate's IP address in Settings"
            case .noNetwork: "Allow Local Network for Camera C64 in Settings"
            case .wrongPassword: "Check the Ultimate's password in Settings"
            case .refused(let reason): reason
            }
        }
    }

    /// How long to wait for the Ultimate, in seconds.
    static let timeout: TimeInterval = 8

    /// The address in Settings: a host name or an IP address, with a port if
    /// need be, or a URL.
    var address: String
    /// The Ultimate's network password, or empty for none.
    var password = ""

    /// The URL of one of the API's routes, such as "runners:run_prg", or nil
    /// if the address is not one.
    func url(route: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else {
            return nil
        }
        components.path = "/v1/" + route
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// The request that runs a program: its .prg file, sent as it is.
    func runRequest(_ program: [UInt8]) -> URLRequest? {
        guard let url = url(route: "runners:run_prg") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if !password.isEmpty {
            request.setValue(password, forHTTPHeaderField: "X-Password")
        }
        request.httpBody = Data(program)
        return request
    }

    /// Resets the C64 and runs a program on it.
    func run(_ program: [UInt8]) async throws(Failure) {
        guard let request = runRequest(program) else { throw .badAddress }
        let answer: Data
        let response: URLResponse
        do {
            (answer, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw Self.failure(error)
        } catch {
            throw .notFound
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 {
            throw .wrongPassword
        }
        let errors = Self.errors(in: answer)
        guard (200..<300).contains(status), errors.isEmpty else {
            throw .refused(errors.first ?? "The Ultimate answered \(status)")
        }
    }

    /// What a failed request means for the user.
    static func failure(_ error: URLError) -> Failure {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .noNetwork
        case .appTransportSecurityRequiresSecureConnection:
            .notLocal
        case .badURL, .unsupportedURL:
            .badAddress
        default:
            .notFound
        }
    }

    /// The API's answers are JSON, whose "errors" list what went wrong.
    nonisolated private struct Answer: Decodable {
        var errors: [String]?
    }

    /// What went wrong, as one of the API's answers says.
    static func errors(in answer: Data) -> [String] {
        (try? JSONDecoder().decode(Answer.self, from: answer))?.errors ?? []
    }
}
