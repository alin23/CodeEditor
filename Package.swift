// swift-tools-version:5.5

import PackageDescription

let package = Package(

  name: "CodeEditor",

  platforms: [
    .macOS(.v11), .iOS(.v14)
  ],

  products: [
    .library(name: "CodeEditor", targets: [ "CodeEditor" ])
  ],

  dependencies: [
    .package(url: "https://github.com/raspu/Highlightr", branch: "master")
  ],

  targets: [
    .target(name: "CodeEditor", dependencies: [ "Highlightr" ])
  ]
)
