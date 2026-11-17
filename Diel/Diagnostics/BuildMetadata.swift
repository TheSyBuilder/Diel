#if DEBUG
  import Foundation

  nonisolated struct BuildMetadata: Decodable, Equatable, Sendable {
    let commit: String
    let dirty: Bool?

    static let current: BuildMetadata = {
      guard let url = Bundle.main.url(forResource: "BuildMetadata", withExtension: "json"),
        let data = try? Data(contentsOf: url),
        let metadata = try? JSONDecoder().decode(BuildMetadata.self, from: data)
      else { return BuildMetadata(commit: "", dirty: nil) }
      return metadata
    }()

    var displayValue: String {
      guard commit.count == 40,
        commit.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) })
      else { return "Unavailable" }
      let short = String(commit.prefix(12))
      switch dirty {
      case true: return "\(short) · Uncommitted changes"
      case false: return short
      case nil: return "\(short) · Changes not checked"
      }
    }
  }
#endif
