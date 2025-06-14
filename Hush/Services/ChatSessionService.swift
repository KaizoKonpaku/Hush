import Foundation
import SwiftUI

/// Data structure for a chat session
struct ChatSession: Codable {
    /// Unique identifier for the session
    let id: UUID
    
    /// Timestamp when the session was created
    let createdAt: Date
    
    /// Timestamp of the last modification
    var lastUpdatedAt: Date
    
    /// User messages and AI responses
    var messages: [ChatMessage]
    
    /// Create a new chat session
    init(id: UUID = UUID(), messages: [ChatMessage] = []) {
        self.id = id
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
        self.messages = messages
    }
}

/// Represents a message in the chat
struct ChatMessage: Codable {
    /// Unique identifier for the message
    let id: UUID
    
    /// Timestamp when the message was sent
    let timestamp: Date
    
    /// Content of the message
    let content: String
    
    /// Type of sender (user or AI)
    let sender: MessageSender
    
    /// Optional metadata for the message
    var metadata: [String: String]?
    
    /// Create a new chat message
    init(id: UUID = UUID(), content: String, sender: MessageSender, timestamp: Date = Date(), metadata: [String: String]? = nil) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Represents the sender of a message
enum MessageSender: String, Codable {
    case user
    case ai
}

/// Service responsible for saving and loading chat sessions
final class ChatSessionService {
    // MARK: - Properties
    
    /// Directory where chat sessions are saved
    private let savedChatsDirectory: URL
    
    /// Currently active chat session
    private(set) var currentSession: ChatSession?
    
    /// File extension for saved chats
    private let fileExtension = "json"
    
    /// Date formatter for filename generation
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    // MARK: - Initialization
    
    /// Shared instance of the service
    static let shared = ChatSessionService()
    
    /// Initialize the chat session service
    init() {
        // Get the Documents directory which is more reliable for user data
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Create the saved_chats directory in Documents
        savedChatsDirectory = documentsDirectory.appendingPathComponent("saved_chats", isDirectory: true)
        
        // Create directory if needed
        createSavedChatsDirectoryIfNeeded()
        
        // Log the path for debugging
        print("📂 Chat storage directory: \(savedChatsDirectory.path)")
    }
    
    // MARK: - Public Methods
    
    /// Start a new chat session
    /// - Returns: The newly created chat session
    @discardableResult
    func startNewSession() -> ChatSession {
        // Save current session if it exists
        if currentSession != nil {
            saveCurrentSession()
        }
        
        // Create a new session
        currentSession = ChatSession()
        print("🆕 Started new chat session: \(currentSession!.id.uuidString)")
        
        // Save the new session to disk immediately
        saveCurrentSession()
        
        return currentSession!
    }
    
    /// Add a user message to the current session
    /// - Parameter message: The message text to add
    /// - Returns: The added message
    @discardableResult
    func addUserMessage(_ message: String) -> ChatMessage? {
        guard currentSession != nil else { 
            print("❌ No active chat session to add user message")
            return nil
        }
        
        let chatMessage = ChatMessage(content: message, sender: .user)
        currentSession?.messages.append(chatMessage)
        currentSession?.lastUpdatedAt = Date()
        
        // Save after each message to ensure no data loss
        saveCurrentSession()
        print("👤 Added user message to chat: \(message.prefix(20))...")
        
        return chatMessage
    }
    
    /// Add an AI response to the current session
    /// - Parameter response: The AI response text to add
    /// - Returns: The added message
    @discardableResult
    func addAIResponse(_ response: String) -> ChatMessage? {
        guard currentSession != nil else { 
            print("❌ No active chat session to add AI response")
            return nil
        }
        
        let chatMessage = ChatMessage(content: response, sender: .ai)
        currentSession?.messages.append(chatMessage)
        currentSession?.lastUpdatedAt = Date()
        
        // Save after each message to ensure no data loss
        saveCurrentSession()
        print("🤖 Added AI response to chat: \(response.prefix(20))...")
        
        return chatMessage
    }
    
    /// Save the current session to disk
    func saveCurrentSession() {
        guard let session = currentSession else {
            print("❌ No chat session to save")
            return
        }
        
        // Don't save empty sessions
        if session.messages.isEmpty {
            print("ℹ️ Not saving empty chat session")
            return
        }
        
        // Check if chat saving is enabled
        if !AppPreferences.shared.saveChatsLocally {
            print("ℹ️ Chat saving is disabled in settings")
            return
        }
        
        do {
            // Ensure directory exists before saving
            createSavedChatsDirectoryIfNeeded()
            
            let fileURL = generateFileURL(for: session)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
            
            print("📝 Chat session saved to: \(fileURL.path)")
            print("   - Messages: \(session.messages.count)")
            print("   - Last update: \(session.lastUpdatedAt)")
        } catch {
            print("❌ Failed to save chat session: \(error.localizedDescription)")
            // Try to diagnose the issue
            diagnoseWriteFailure(error: error)
        }
    }
    
    /// Close the current session and save it
    func closeCurrentSession() {
        print("🔒 Closing chat session")
        saveCurrentSession()
        currentSession = nil
    }
    
    /// List all saved chat sessions
    /// - Returns: Array of saved chat sessions
    func listSavedSessions() -> [ChatSession] {
        var sessions: [ChatSession] = []
        
        do {
            // Ensure directory exists
            createSavedChatsDirectoryIfNeeded()
            
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: savedChatsDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for fileURL in fileURLs where fileURL.pathExtension == fileExtension {
                if let session = loadSession(from: fileURL) {
                    sessions.append(session)
                }
            }
            
            print("📋 Listed \(sessions.count) saved chat sessions")
        } catch {
            print("❌ Failed to list saved chat sessions: \(error.localizedDescription)")
        }
        
        return sessions.sorted(by: { $0.createdAt > $1.createdAt })
    }
    
    // MARK: - Private Methods
    
    /// Create the saved chats directory if it doesn't exist
    private func createSavedChatsDirectoryIfNeeded() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: savedChatsDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: savedChatsDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                print("📁 Created saved_chats directory at: \(savedChatsDirectory.path)")
                
                // Create a .nomedia file to hide from media scanners on some platforms
                let noMediaURL = savedChatsDirectory.appendingPathComponent(".nomedia")
                try "".write(to: noMediaURL, atomically: true, encoding: .utf8)
            } catch {
                print("❌ Failed to create saved_chats directory: \(error.localizedDescription)")
                diagnoseDirectoryCreationFailure(error: error)
            }
        }
    }
    
    /// Generate a unique file URL for a chat session
    /// - Parameter session: The chat session
    /// - Returns: A unique file URL
    private func generateFileURL(for session: ChatSession) -> URL {
        let dateString = dateFormatter.string(from: session.createdAt)
        let filename = "chat_\(dateString)_\(session.id.uuidString).\(fileExtension)"
        return savedChatsDirectory.appendingPathComponent(filename)
    }
    
    /// Load a chat session from a file URL
    /// - Parameter fileURL: URL of the chat session file
    /// - Returns: The loaded chat session, or nil if loading failed
    private func loadSession(from fileURL: URL) -> ChatSession? {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ChatSession.self, from: data)
        } catch {
            print("❌ Failed to load chat session from \(fileURL.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Diagnose directory creation failure
    /// - Parameter error: The error that occurred
    private func diagnoseDirectoryCreationFailure(error: Error) {
        let fileManager = FileManager.default
        
        // Check parent directory
        let parentDir = savedChatsDirectory.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            print("⚠️ Parent directory doesn't exist: \(parentDir.path)")
        } else {
            // Check permissions
            if !fileManager.isWritableFile(atPath: parentDir.path) {
                print("⚠️ Parent directory is not writable: \(parentDir.path)")
            }
        }
        
        // Try to create a temporary file to check write permissions
        let tempFile = parentDir.appendingPathComponent("hush_write_test.tmp")
        do {
            try "test".write(to: tempFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: tempFile)
            print("✅ Parent directory is writable")
        } catch {
            print("⚠️ Cannot write to parent directory: \(error.localizedDescription)")
        }
    }
    
    /// Diagnose file write failure
    /// - Parameter error: The error that occurred
    private func diagnoseWriteFailure(error: Error) {
        let fileManager = FileManager.default
        
        // Check if directory exists
        if !fileManager.fileExists(atPath: savedChatsDirectory.path) {
            print("⚠️ Saved chats directory doesn't exist")
        } else {
            // Check permissions
            if !fileManager.isWritableFile(atPath: savedChatsDirectory.path) {
                print("⚠️ Saved chats directory is not writable")
            }
        }
        
        // Check free space
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: savedChatsDirectory.path)
            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                print("ℹ️ Free space: \(ByteCountFormatter.string(fromByteCount: freeSpace.int64Value, countStyle: .file))")
            }
        } catch {
            print("⚠️ Unable to check free space: \(error.localizedDescription)")
        }
    }
} 