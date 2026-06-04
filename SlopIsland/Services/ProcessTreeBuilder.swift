import Foundation

struct ProcessInfo {
    let pid: Int
    let ppid: Int
    let command: String
}

struct ProcessTreeBuilder {
    static let shared = ProcessTreeBuilder()

    func buildTree() -> [Int: ProcessInfo] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,ppid,comm"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var tree: [Int: ProcessInfo] = [:]
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 3,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else { continue }
            let command = parts.dropFirst(2).joined(separator: " ")
            tree[pid] = ProcessInfo(pid: pid, ppid: ppid, command: command)
        }
        return tree
    }

    func findTerminalPID(forProcess pid: Int, tree: [Int: ProcessInfo]) -> Int? {
        var current = pid
        var visited = Set<Int>()
        while let info = tree[current] {
            if visited.contains(current) { break }
            visited.insert(current)
            if TerminalAppRegistry.isTerminal(info.command) {
                return current
            }
            current = info.ppid
            if current == 0 { break }
        }
        return nil
    }
}
