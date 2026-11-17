// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "ScoringKit",
  platforms: [.iOS(.v27), .macOS(.v27)],
  products: [.library(name: "ScoringKit", targets: ["ScoringKit"])],
  targets: [.target(name: "ScoringKit")],
  swiftLanguageModes: [.v6]
)
