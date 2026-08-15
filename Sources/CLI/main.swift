import Foundation

// Test and scripting front end for Core. The GUI uses the same types.
//
//   rcshare <destination> <path>...
//   rcshare <destination> --text <filename>     content is read from stdin
//   rcshare --list

let usage = """
usage:
  rcshare <destination> <path>...
  rcshare <destination> --text <filename>   # content from stdin
  rcshare --list

destinations:
\(Destination.all.map { "  \($0.id)\t\($0.displayName) → \($0.remoteFolderPath)" }.joined(separator: "\n"))
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}

if arguments == ["--list"] {
    for destination in Destination.all {
        print("\(destination.id)\t\(destination.displayName)\t\(destination.remoteFolderPath)")
    }
    exit(0)
}

let destinationID = arguments.removeFirst()
guard let destination = Destination.named(destinationID) else {
    fail("unknown destination '\(destinationID)'. Known: \(Destination.all.map(\.id).joined(separator: ", "))")
}

let uploader = Uploader()

do {
    let result: UploadResult

    if arguments.first == "--text" {
        guard arguments.count == 2 else { fail("--text needs exactly one filename") }
        let filename = arguments[1]
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let text = String(data: input, encoding: .utf8) ?? ""
        result = try uploader.upload(text: text, filename: filename, to: destination)
    } else {
        let paths = arguments.map { URL(fileURLWithPath: $0) }
        for path in paths where !FileManager.default.fileExists(atPath: path.path) {
            fail("no such file: \(path.path)")
        }
        result = try uploader.upload(paths: paths, to: destination)
    }

    print(result.link.absoluteString)
} catch {
    fail(error.localizedDescription)
}
