import Foundation

/// One AskUserQuestion invocation. Claude may bundle several questions in a
/// single call (e.g. 类型 / 配色 / 渲染 / 画幅); each is a `QuestionItem`.
struct UserQuestion {
    let sessionID: String
    let cwd: String
    let items: [QuestionItem]
}

struct QuestionItem {
    let header: String
    let prompt: String
    let options: [QuestionOption]
    let multiSelect: Bool
}

struct QuestionOption {
    let label: String
    let description: String?
}
