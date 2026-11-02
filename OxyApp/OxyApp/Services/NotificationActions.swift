import Foundation
import UserNotifications

extension Notification.Name {
    static let adamOpenItem = Notification.Name("adam.openItem")
}

struct NotificationAnswer: Sendable {
    enum Kind: Sendable { case approve, decline, reply(String), open }

    let kind: Kind
    let identifier: String
    let workflowId: String?
    let checkpointId: String?
    let approvalId: String?
    let taskId: String?
    let conversationId: String?

    init(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        func text(_ key: String) -> String? {
            let value = info[key] as? String
            return (value?.isEmpty ?? true) ? nil : value
        }
        identifier = response.notification.request.identifier
        workflowId = text("workflowId")
        checkpointId = text("checkpointId")
        approvalId = text("approvalId")
        taskId = text("taskId")
        conversationId = text("conversationId")
        switch response.actionIdentifier {
        case NotificationActions.Action.approve: kind = .approve
        case NotificationActions.Action.decline: kind = .decline
        case NotificationActions.Action.reply:
            kind = .reply((response as? UNTextInputNotificationResponse)?.userText ?? "")
        default: kind = .open
        }
    }
}

enum NotificationActions {
    enum Category {
        static let approve = "adam.approve"
        static let approveUnlock = "adam.approve.unlock"
        static let choose = "adam.choose"
        static let reply = "adam.reply"
        static let result = "adam.result"
    }

    enum Action {
        static let approve = "adam.action.approve"
        static let decline = "adam.action.decline"
        static let reply = "adam.action.reply"
        static let open = "adam.action.open"
        static let see = "adam.action.see"
    }

    static func register() {
        func approve(unlock: Bool) -> UNNotificationAction {
            UNNotificationAction(identifier: Action.approve, title: "Approve", options: unlock ? [.authenticationRequired] : [])
        }
        let decline = UNNotificationAction(identifier: Action.decline, title: "Decline", options: [.destructive])
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply to Adam"
        )
        let open = UNNotificationAction(identifier: Action.open, title: "Open", options: [.foreground])
        let see = UNNotificationAction(identifier: Action.see, title: "See it", options: [.foreground])
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Category.approve, actions: [approve(unlock: false), decline, reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.approveUnlock, actions: [approve(unlock: true), decline], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.choose, actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.reply, actions: [reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.result, actions: [see], intentIdentifiers: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    static func handle(_ answer: NotificationAnswer) async {
        guard let userId = KeychainHelper.shared.read(key: "user_id"), !userId.isEmpty else {
            await openApp(answer)
            return
        }
        do {
            switch answer.kind {
            case .open:
                await openApp(answer)
                return
            case .approve, .decline:
                let approved: Bool
                if case .approve = answer.kind { approved = true } else { approved = false }
                if let workflowId = answer.workflowId, let checkpointId = answer.checkpointId {
                    try await HomeBoardService.resolveCheckpoint(workflowId: workflowId, checkpointId: checkpointId, approved: approved)
                } else if let approvalId = answer.approvalId, let taskId = answer.taskId {
                    try await AgentTasksService.decide(approvalId: approvalId, taskId: taskId, approved: approved)
                } else {
                    await openApp(answer)
                    return
                }
            case .reply(let text):
                let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { return }
                _ = try await APIClient.shared.request(path: "/chat", method: "POST", body: ["userId": userId, "message": message])
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [answer.identifier])
        } catch {
            await tell(error.localizedDescription)
        }
    }

    @MainActor
    private static func postOpen(_ answer: NotificationAnswer) {
        var info: [String: String] = [:]
        if let id = answer.checkpointId ?? answer.approvalId ?? answer.workflowId { info["itemId"] = id }
        NotificationCenter.default.post(name: .adamOpenItem, object: nil, userInfo: info)
    }

    private static func openApp(_ answer: NotificationAnswer) async {
        await postOpen(answer)
    }

    private static func tell(_ message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Adam"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
