import Foundation
@testable import VoltaneKit

enum TestResources {
    static func url(_ path: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent(path)
    }

    static func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }
}
