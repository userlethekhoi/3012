import Foundation

public enum PackagePathError: Error, Equatable {
    case empty
    case tooLong
    case absolute
    case backslash
    case unsafeComponent
}

public enum PackagePathValidator {
    public static func validate(_ relativePath: String) throws {
        guard !relativePath.isEmpty else { throw PackagePathError.empty }
        guard relativePath.utf8.count <= 1_024 else { throw PackagePathError.tooLong }
        guard !relativePath.hasPrefix("/") else { throw PackagePathError.absolute }
        guard !relativePath.contains("\\") else { throw PackagePathError.backslash }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".."
        }) else {
            throw PackagePathError.unsafeComponent
        }
    }

    public static func destination(root: URL, relativePath: String) throws -> URL {
        try validate(relativePath)
        let standardizedRoot = root.standardizedFileURL
        let destination = standardizedRoot
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        guard destination.path.hasPrefix(rootPrefix) else {
            throw PackagePathError.absolute
        }
        return destination
    }
}
