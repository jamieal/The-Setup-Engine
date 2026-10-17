// Re-saves a JPEG with no metadata: no GPS location, camera, dates or
// anything else from the original, only the orientation (so it still shows
// the right way up). Used by publish-wallpapers.sh before anything is uploaded.
//
//   swift scripts/strip-photo-metadata.swift <in.jpg> <out.jpg>

import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: strip-photo-metadata <in> <out>\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: args[1]) as CFURL
let output = URL(fileURLWithPath: args[2]) as CFURL

guard let source = CGImageSourceCreateWithURL(input, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let destination = CGImageDestinationCreateWithURL(output, UTType.jpeg.identifier as CFString, 1, nil)
else {
    FileHandle.standardError.write(Data("couldn't read \(args[1])\n".utf8))
    exit(1)
}

let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
if let orientation = original?[kCGImagePropertyOrientation] {
    properties[kCGImagePropertyOrientation] = orientation
}

CGImageDestinationAddImage(destination, image, properties as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("couldn't write \(args[2])\n".utf8))
    exit(1)
}
