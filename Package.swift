// swift-tools-version:5.9
import PackageDescription

// v0.2 · Tres módulos:
//   FotosCore       → lógica pura (solo Foundation): opciones, reglas, informe, lista del álbum,
//                     y los textos traducidos (Resources/<idioma>.lproj). Se prueba sin iPhone.
//   FotosIPhoneKit  → todo lo que habla con el iPhone (ImageCaptureCore, AVFoundation).
//   fotos-iphone    → la herramienta de Terminal.
// La app de la v0.3 usará FotosCore y FotosIPhoneKit.
let package = Package(
    name: "fotos-iphone",
    defaultLocalization: "es",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FotosCore", targets: ["FotosCore"]),
        .library(name: "FotosIPhoneKit", targets: ["FotosIPhoneKit"]),
        .executable(name: "fotos-iphone", targets: ["fotos-iphone"]),
    ],
    targets: [
        .target(
            name: "FotosCore",
            path: "Sources/FotosCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "FotosIPhoneKit",
            dependencies: ["FotosCore"],
            path: "Sources/FotosIPhoneKit",
            linkerSettings: [
                .linkedFramework("ImageCaptureCore"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "fotos-iphone",
            dependencies: ["FotosCore", "FotosIPhoneKit"],
            path: "Sources/fotos-iphone"
        ),
        .testTarget(
            name: "FotosCoreTests",
            dependencies: ["FotosCore"],
            path: "Tests/FotosCoreTests"
        ),
    ]
)
