// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"BlueprintCreator",platforms:[.macOS(.v13)],products:[.executable(name:"BlueprintCreator",targets:["BlueprintCreator"])],targets:[.executableTarget(name:"BlueprintCreator",path:"Sources/BlueprintCreator")])
