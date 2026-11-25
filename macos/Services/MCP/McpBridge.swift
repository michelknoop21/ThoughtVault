#if os(macOS)
import Foundation

/// `ThoughtVault --mcp`: the stdio server an MCP client starts. Starts no UI; it connects to
/// the running app (McpServer) and copies lines between stdin/stdout and that socket.
/// Runs inside the same sandbox container as the app, so it can read mcp.json.
enum McpBridge {
    static var isRequested: Bool { CommandLine.arguments.contains("--mcp") }

    static func run(fileURL: URL = McpServer.fileURL) -> Never {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = file["port"] as? Int, let token = file["token"] as? String,
              let socket = connect(port: UInt16(clamping: port)) else {
            fail("ThoughtVault is niet geopend of de AI-koppeling staat uit.")
        }
        // A closed pipe on either side ends the copy loop instead of killing the process.
        signal(SIGPIPE, SIG_IGN)
        guard write(socket, Data((token + "\n").utf8)) else { fail("Verbinding met ThoughtVault mislukt.") }
        // socket -> stdout on its own thread; stdin -> socket here. Either side closing ends the process.
        Thread.detachNewThread {
            copy(from: socket, to: FileHandle.standardOutput.fileDescriptor)
            exit(0)
        }
        copy(from: FileHandle.standardInput.fileDescriptor, to: socket)
        shutdown(socket, SHUT_WR)
        // Let the app answer what is still in flight; the reader thread exits when the app closes.
        Thread.sleep(forTimeInterval: 30)
        exit(0)
    }

    private static func connect(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 { close(fd); return nil }
        return fd
    }

    private static func copy(from source: Int32, to target: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(source, &buffer, buffer.count)
            if count <= 0 { return }
            if !write(target, Data(buffer[0..<count])) { return }
        }
    }

    private static func write(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
#endif
