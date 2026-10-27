import UniformTypeIdentifiers

/// What Glina's backend writes into an assets directory, told apart by the
/// content type the system records for each file rather than by comparing
/// file names. The GLB container has no system declaration, so its type is
/// the one the system derives from the `.glb` name the backend gives it.
enum AssetKind {
    case model, animation, still

    static let modelType = UTType(filenameExtension: "glb")

    init?(contentType: UTType) {
        if let model = Self.modelType, contentType.conforms(to: model) {
            self = .model
        } else if contentType.conforms(to: .gif) {
            self = .animation
        } else if contentType.conforms(to: .png) {
            self = .still
        } else {
            return nil
        }
    }
}
