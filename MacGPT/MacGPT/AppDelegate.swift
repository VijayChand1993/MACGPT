
import Cocoa
import Down

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, URLSessionDataDelegate {

    var window: NSWindow!
    let chatHistory = NSTextView()
    var chatScrollView: NSScrollView!

    class PlaceholderTextView: NSTextView {
        var placeholder: String = "Type your message..." {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.placeholderTextColor,
                    .font: font ?? NSFont.systemFont(ofSize: 13),
                    .paragraphStyle: paragraphStyle
                ]
                let placeholderRect = NSRect(x: 5, y: 4, width: bounds.width - 10, height: bounds.height)
                placeholder.draw(in: placeholderRect, withAttributes: attributes)
            }
        }

        override var string: String {
            didSet { needsDisplay = true }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
                (delegate as? AppDelegate)?.sendPressed()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    let userInput = PlaceholderTextView()
    var inputScrollView: NSScrollView!
    var inputScrollViewHeightConstraint: NSLayoutConstraint!
    let sendButton = NSButton(title: "Send", target: nil, action: #selector(sendPressed))

    var urlSession: URLSession?
    var dataTask: URLSessionDataTask?
    var streamingResponse = ""
    let chatHistoryKey = "chat_history"

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let windowSize = NSRect(x: 300, y: 300, width: 400, height: 600)
        window = NSWindow(contentRect: windowSize,
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "MacGPT"
        window.backgroundColor = .white
        window.level = .screenSaver
        window.isOpaque = false
        // window.backgroundColor = .white
        window.sharingType = .none // Hide from screen share
        window.isRestorable = false

        // Chat history scroll view + text view setup
        chatHistory.isEditable = false
        chatHistory.isSelectable = true
        chatHistory.font = NSFont.systemFont(ofSize: 13)
        chatHistory.backgroundColor = .white
        chatHistory.isVerticallyResizable = true
        chatHistory.isHorizontallyResizable = false // Disable horizontal resizing for word wrap
        chatHistory.textContainerInset = NSSize(width: 5, height: 5)
        chatHistory.textContainer?.widthTracksTextView = true
        // Set initial container width to match window size minus padding
        let initialWidth = windowSize.width - 20
        chatHistory.textContainer?.containerSize = NSSize(width: initialWidth, height: .greatestFiniteMagnitude)
        chatHistory.textContainer?.lineBreakMode = .byWordWrapping
        chatHistory.autoresizingMask = [.width]
        chatHistory.translatesAutoresizingMaskIntoConstraints = true
        chatHistory.frame = NSRect(x: 0, y: 0, width: initialWidth, height: 1000)

        chatScrollView = NSScrollView()
        chatScrollView.documentView = chatHistory
        chatScrollView.hasVerticalScroller = true
        chatScrollView.hasHorizontalScroller = false // Disable horizontal scroll
        chatScrollView.autohidesScrollers = true
        chatScrollView.borderType = .noBorder
        chatScrollView.backgroundColor = .white
        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(chatScrollView)

        // Ensure text wraps to the scroll view width on resize
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: chatScrollView.contentView, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            // Match chatHistory container width to chatScrollView width (window minus padding)
            let width = self.chatScrollView.contentSize.width
            self.chatHistory.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            self.chatHistory.textContainer?.widthTracksTextView = true
            self.chatHistory.frame.size.width = width
        }
        chatScrollView.contentView.postsFrameChangedNotifications = true

        // User input
        userInput.isEditable = true
        userInput.isSelectable = true
        userInput.font = NSFont.systemFont(ofSize: 13)
        userInput.delegate = self
        userInput.isVerticallyResizable = true
        userInput.isHorizontallyResizable = false
        userInput.textContainer?.widthTracksTextView = true
        userInput.textContainer?.containerSize = NSSize(width: windowSize.width - 100, height: .greatestFiniteMagnitude)
        userInput.wantsLayer = true
        userInput.backgroundColor = NSColor.systemGray.withAlphaComponent(0.15)
        userInput.layer?.borderColor = NSColor.black.cgColor
        userInput.layer?.borderWidth = 1
        userInput.layer?.cornerRadius = 4
        userInput.placeholder = "Type your message..."

        inputScrollView = NSScrollView()
        inputScrollView.documentView = userInput
        inputScrollView.hasVerticalScroller = false
        inputScrollView.drawsBackground = true
        inputScrollView.backgroundColor = .clear
        inputScrollView.translatesAutoresizingMaskIntoConstraints = false
        inputScrollView.wantsLayer = true
        inputScrollView.layer?.borderColor = NSColor.clear.cgColor
        inputScrollView.layer?.borderWidth = 0
        window.contentView?.addSubview(inputScrollView)

        userInput.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            userInput.leadingAnchor.constraint(equalTo: inputScrollView.leadingAnchor),
            userInput.trailingAnchor.constraint(equalTo: inputScrollView.trailingAnchor),
            userInput.topAnchor.constraint(equalTo: inputScrollView.topAnchor),
            userInput.bottomAnchor.constraint(equalTo: inputScrollView.bottomAnchor)
        ])

        sendButton.bezelStyle = .rounded
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.target = self
        sendButton.action = #selector(sendPressed)
        window.contentView?.addSubview(sendButton)

        guard let contentView = window.contentView else { return }
        NSLayoutConstraint.activate([
            chatScrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            chatScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            chatScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

            inputScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            inputScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            inputScrollView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),

            sendButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            sendButton.bottomAnchor.constraint(equalTo: inputScrollView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),
            sendButton.heightAnchor.constraint(equalToConstant: 30),

            chatScrollView.bottomAnchor.constraint(equalTo: inputScrollView.topAnchor, constant: -10)
        ])

        inputScrollViewHeightConstraint = inputScrollView.heightAnchor.constraint(equalToConstant: 40)
        inputScrollViewHeightConstraint.isActive = true

        loadChatHistory()
        if let saved = UserDefaults.standard.attributedString(forKey: chatHistoryKey) {
            chatHistory.textStorage?.setAttributedString(saved)
        }
        // Always scroll to bottom after loading
        chatHistory.scrollToEndOfDocument(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let maxHeight: CGFloat = 150
            var newHeight = usedRect.height + 10
            if newHeight > maxHeight {
                newHeight = maxHeight
                inputScrollView.hasVerticalScroller = true
            } else {
                inputScrollView.hasVerticalScroller = false
            }
            inputScrollViewHeightConstraint.constant = newHeight
            window.layoutIfNeeded()
        }
    }

    @objc func sendPressed() {
        let prompt = userInput.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        appendToChatHistory(role: "user", markdown: prompt)
        userInput.string = ""
        streamingResponse = ""

        fetchChatGPTResponse(prompt: prompt)
    }

    func markdownToAttributedString(_ markdown: String) -> NSAttributedString {
        // Use Down for advanced markdown parsing with whitespace and newlines preserved
        do {
            let down = Down(markdownString: markdown)
            // Use a modern, readable font and larger size for all markdown text
            let stylesheet = """
                body, p, li, ul, ol, h1, h2, h3, h4, h5, h6 {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 16px;
                }
                code, pre {
                    font-family: 'JetBrains Mono', 'Menlo', 'SF Mono', 'Consolas', monospace;
                    font-size: 15px;
                }
            """
            let attributed = try down.toAttributedString(
                .default,
                stylesheet: stylesheet
            )
            return attributed
        } catch {
            print("Markdown parsing failed: \(error)")
            return NSAttributedString(string: markdown)
        }
    }

    func appendToChatHistory(role: String, markdown: String) {
        let attributed = markdownToAttributedString(markdown)
        // print("Appending to chat history: \(role) - \(attributed.string)")
        let bubble = NSMutableAttributedString()

        let senderColor: NSColor = (role == "user") ? .systemBlue : .systemRed
        let name = (role == "user") ? "You: " : "Assistant: "
        let header = NSAttributedString(
            string: name,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13),
                         .foregroundColor: senderColor]
        )

        bubble.append(header)
        bubble.append(NSAttributedString(string: "\n"))
        bubble.append(attributed)
        bubble.append(NSAttributedString(string: "\n\n"))

        chatHistory.textStorage?.append(bubble)
        chatHistory.scrollToEndOfDocument(nil)
        saveChatHistory()
    }

    func saveChatHistory() {
        UserDefaults.standard.set(chatHistory.attributedString().string, forKey: chatHistoryKey)
    }

    func loadChatHistory() {
        if let saved = UserDefaults.standard.string(forKey: chatHistoryKey) {
            chatHistory.string = saved
        }
    }

    func fetchChatGPTResponse(prompt: String) {
        let apiKey = "" // Replace with your actual OpenAI API key
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let json: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: json)

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        dataTask = urlSession?.dataTask(with: request)
        dataTask?.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        // print("Received chunk: \(chunk)")
        let lines = chunk.components(separatedBy: "\n")
        for line in lines {
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = line.replacingOccurrences(of: "data: ", with: "")
            if jsonString == "[DONE]" {
                dataTask.cancel()
                // On DONE, just clear the buffer; do not append again to avoid duplicate messages
                streamingResponse = ""
                return
            }

            if let jsonData = jsonString.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let choices = jsonObject["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                streamingResponse += content
                // Live update: remove last assistant message and append the current streaming response
                removeLastAssistantMessageIfNeeded()
                appendToChatHistory(role: "assistant", markdown: streamingResponse)
            }
        }

    }

    // Helper to remove the last assistant message (if any) to avoid duplicate streaming
    func removeLastAssistantMessageIfNeeded() {
        guard let storage = chatHistory.textStorage else { return }
        let fullString = storage.string as NSString
        let userHeader = "You: "
        let assistantHeader = "Assistant: "
        // Find the last 'Assistant: ' header that comes after the last 'You: '
        let lastUserRange = fullString.range(of: userHeader, options: .backwards)
        let lastAssistantRange = fullString.range(of: assistantHeader, options: .backwards)
        if lastAssistantRange.location != NSNotFound {
            // Only remove if the last assistant message is after the last user message
            if lastUserRange.location == NSNotFound || lastAssistantRange.location > lastUserRange.location {
                storage.deleteCharacters(in: NSRange(location: lastAssistantRange.location, length: fullString.length - lastAssistantRange.location))
            }
        }
    }
}

// MARK: - UserDefaults extension to store/load NSAttributedString
extension UserDefaults {
    func setAttributedString(_ value: NSAttributedString, forKey defaultName: String) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
            self.set(data, forKey: defaultName)
        } catch {
            print("Failed to archive attributed string: \(error)")
        }
    }

    func attributedString(forKey defaultName: String) -> NSAttributedString? {
        if let data = self.data(forKey: defaultName) {
            do {
                return try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? NSAttributedString
            } catch {
                print("Failed to unarchive attributed string: \(error)")
            }
        }
        return nil
    }
}
