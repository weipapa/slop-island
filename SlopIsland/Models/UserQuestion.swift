import Foundation

struct UserQuestion {
    let sessionID: String
    let cwd: String
    let question: String
    let options: [QuestionOption]
}

struct QuestionOption {
    let label: String
    let description: String?
}
