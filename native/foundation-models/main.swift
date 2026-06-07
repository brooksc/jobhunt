// Persistent subprocess bridge to Apple's FoundationModels framework.
// Reads newline-delimited JSON requests from stdin, writes responses to stdout.
// One process kept alive by the Node.js server — many requests, no startup cost.
//
// Request:  {"id":"...","system":"...","prompt":"..."}
// Response: {"id":"...","content":"...","error":null}
import FoundationModels
import Foundation

struct Req: Codable {
  let id: String
  let system: String?
  let prompt: String
}

struct Resp: Codable {
  let id: String
  let content: String?
  let error: String?
}

func send(_ resp: Resp) {
  if let data = try? JSONEncoder().encode(resp),
     let line = String(data: data, encoding: .utf8) {
    print(line)
    fflush(stdout)
  }
}

func run() async {
  print("{\"ready\":true}")
  fflush(stdout)

  for await line in AsyncStream(String.self, { cont in
    DispatchQueue.global().async {
      while let l = readLine() { cont.yield(l) }
      cont.finish()
    }
  }) {
    guard let data = line.data(using: .utf8),
          let req = try? JSONDecoder().decode(Req.self, from: data) else {
      continue
    }
    do {
      let instructions = req.system ?? "You are a helpful assistant. Follow the user's instructions precisely."
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(to: req.prompt)
      send(Resp(id: req.id, content: response.content, error: nil))
    } catch {
      send(Resp(id: req.id, content: nil, error: error.localizedDescription))
    }
  }
}

RunLoop.main.perform {
  Task { await run() }
}
RunLoop.main.run()
