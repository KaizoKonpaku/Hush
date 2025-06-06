import Foundation
import Combine
import AppKit

/// Service for interacting with the Google Gemini API
final class GeminiService: NSObject {
    // MARK: - Properties
    
    /// Base URL for the Gemini API
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    
    /// Default model to use for requests
    private let defaultModel = "gemini-2.0-flash"
    
    /// API key from user preferences
    private var apiKey: String? {
        return AppPreferences.shared.geminiApiKey
    }
    
    /// The current data task for streaming
    private var streamingTask: URLSessionDataTask?
    
    /// The session for streaming requests
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Increase timeouts for better streaming reliability
        configuration.timeoutIntervalForRequest = 60  // 60 seconds for each chunk
        configuration.timeoutIntervalForResource = 300 // 5 minutes total
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    /// Buffer for storing partial SSE events
    private var dataBuffer = Data()
    
    /// Callback when new text chunks arrive
    private var onUpdateCallback: ((String) -> Void)?
    
    /// Callback when streaming is complete
    private var onCompleteCallback: ((String) -> Void)?
    
    /// Callback for structured content updates
    private var onStructuredUpdateCallback: ((StreamContent) -> Void)?
    
    /// Callback when an error occurs
    private var onErrorCallback: ((Error) -> Void)?
    
    /// Accumulated text from all events
    private var fullText = ""
    
    /// Content builder for processing the streaming content
    private var contentBuilder = StreamContentBuilder()
    
    /// Flag to indicate if we're currently streaming
    private var isStreamActive = false
    
    // MARK: - Singleton
    
    /// Shared singleton instance
    static let shared = GeminiService()
    
    /// Private initializer to enforce singleton pattern
    private override init() {
        super.init()
    }
    
    // MARK: - Public Properties
    
    /// Whether the service is configured with a valid API key
    var isConfigured: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    // MARK: - Public Methods
    
    /// Generate a completion with streaming support and structured content processing
    /// - Parameters:
    ///   - prompt: The text prompt to send to the model
    ///   - images: Array of images to include in the request
    ///   - onUpdate: Callback that receives structured content updates
    ///   - onError: Callback if an error occurs
    func generateStructuredStreamingContent(
        prompt: String,
        images: [NSImage] = [],
        onUpdate: @escaping (StreamContent) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            onError(GeminiError.missingAPIKey)
            return
        }
        
        // Store callbacks
        self.onStructuredUpdateCallback = onUpdate
        self.onErrorCallback = onError
        
        // Reset state for new request
        self.dataBuffer = Data()
        self.fullText = ""
        self.contentBuilder = StreamContentBuilder()
        self.isStreamActive = true
        
        // Cancel any ongoing streaming task
        streamingTask?.cancel()
        
        // Create URL with the proper SSE parameter
        guard let url = URL(string: "\(baseURL)/models/\(defaultModel):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            onError(GeminiError.invalidURL)
            return
        }
        
        // Prepare request with appropriate token limits
        let requestBody = generateRequestBodyWithImages(prompt: prompt, images: images)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            // Debug the request
            print("🔵 Streaming request initiated with \(images.count) images")
            print("🔵 Request body size: \(jsonData.count) bytes")
            
            // Create a streaming data task
            streamingTask = session.dataTask(with: request)
            streamingTask?.resume()
        } catch {
            onError(error)
        }
    }
    
    /// Generate a completion from text and images with streaming support
    /// - Parameters:
    ///   - prompt: The text prompt to send to the model
    ///   - images: Array of images to include in the request
    ///   - onUpdate: Callback that receives text updates as they stream in
    ///   - onComplete: Callback when the streaming is complete with final text
    ///   - onError: Callback if an error occurs
    func generateStreamingCompletionWithImages(
        prompt: String,
        images: [NSImage],
                                    onUpdate: @escaping (String) -> Void,
                                    onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            onError(GeminiError.missingAPIKey)
            return
        }
        
        // Store callbacks
        self.onUpdateCallback = onUpdate
        self.onCompleteCallback = onComplete
        self.onErrorCallback = onError
        
        // Reset state for new request
        self.dataBuffer = Data()
        self.fullText = ""
        self.isStreamActive = true
        
        // Cancel any ongoing streaming task
        streamingTask?.cancel()
        
        // Create URL with the proper SSE parameter
        guard let url = URL(string: "\(baseURL)/models/\(defaultModel):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            onError(GeminiError.invalidURL)
            return
        }
        
        // Prepare request with appropriate token limits
        let requestBody = generateRequestBodyWithImages(prompt: prompt, images: images)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            // Debug the request
            print("🔵 Streaming request initiated with \(images.count) images")
            print("🔵 Request body size: \(jsonData.count) bytes")
            
            // Create a streaming data task
            streamingTask = session.dataTask(with: request)
            streamingTask?.resume()
        } catch {
            onError(error)
        }
    }
    
    /// Generate a completion from text input with streaming support
    /// - Parameters:
    ///   - prompt: The text prompt to send to the model
    ///   - onUpdate: Callback that receives text updates as they stream in
    ///   - onComplete: Callback when the streaming is complete with final text
    ///   - onError: Callback if an error occurs
    func generateStreamingCompletion(
        prompt: String, 
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Call the image version with an empty images array
        generateStreamingCompletionWithImages(
            prompt: prompt,
            images: [],
            onUpdate: onUpdate,
            onComplete: onComplete,
            onError: onError
        )
    }
    
    /// Generate a completion from text input (non-streaming version)
    /// - Parameters:
    ///   - prompt: The text prompt to send to the model
    ///   - completion: Callback with the result text or error
    func generateCompletion(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            completion(.failure(GeminiError.missingAPIKey))
            return
        }
        
        guard let url = URL(string: "\(baseURL)/models/\(defaultModel):generateContent?key=\(apiKey)") else {
            completion(.failure(GeminiError.invalidURL))
            return
        }
        
        let requestBody = generateRequestBody(prompt: prompt)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        completion(.failure(GeminiError.noData))
                    }
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first,
                       let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        DispatchQueue.main.async {
                            completion(.success(text))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(GeminiError.invalidResponse))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
            
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
    
    /// Cancel any ongoing streaming request
    func cancelStreaming() {
        // Cancel the streaming task if it exists
        streamingTask?.cancel()
        streamingTask = nil
        
        // Mark the stream as inactive
        isStreamActive = false
        
        // Clear buffers and state
        dataBuffer = Data()
        fullText = ""
        
        // Clear callbacks to prevent execution after cancellation
        clearCallbacks()
        
        print("🔵 Streaming request cancelled")
    }
    
    // MARK: - Private Helper Methods
    
    /// Process a single SSE event
    /// - Parameter eventData: The data for a single event
    private func processEvent(_ eventData: String) {
        // Debug: log the event data length
        print("🟢 Received event chunk with length: \(eventData.count)")
        
        // Check for the [DONE] marker that indicates end of stream
        if eventData.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            print("🟢 Received [DONE] marker")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.isStreamActive = false
                print("🟢 Stream complete, total length: \(self.fullText.count)")
                
                // Handle structured content update if applicable
                if let onStructuredUpdate = self.onStructuredUpdateCallback {
                    // Mark the stream as finished
                    var content = self.contentBuilder.build()
                    content.finished = true
                    onStructuredUpdate(content)
                }
                
                // Handle traditional text callback if applicable
                if let onComplete = self.onCompleteCallback {
                    onComplete(self.fullText)
                }
                
                // Clear callbacks to avoid memory leaks
                self.clearCallbacks()
            }
            return
        }
            
        // Convert the event string to data for JSON parsing
        guard let jsonData = eventData.data(using: .utf8) else { return }
            
        do {
            // Try to parse the JSON response
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // Check for finish reason which might indicate truncation
                if let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let finishReason = firstCandidate["finishReason"] as? String {
                    print("🟡 Stream finished with reason: \(finishReason)")
                    if finishReason != "STOP" && finishReason != "FINISH_REASON_UNSPECIFIED" {
                        // This might indicate truncation or other issues
                        print("⚠️ Potential stream truncation with reason: \(finishReason)")
                    }
                }
                
                // Extract the text from the candidates array
                if let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    
                    print("🟢 Extracted text chunk length: \(text.count)")
                    self.fullText += text
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Handle traditional text callback
                        if let onUpdate = self.onUpdateCallback {
                            onUpdate(text)
                        }
                        
                        // Handle structured content update
                        if let onStructuredUpdate = self.onStructuredUpdateCallback {
                            // Create a new content builder with the updated text
                            self.contentBuilder = StreamContentBuilder(buffer: self.fullText)
                            let content = self.contentBuilder.build()
                            onStructuredUpdate(content)
                        }
                    }
                }
            }
        } catch {
            print("🔴 Error parsing event: \(error.localizedDescription)")
            // Skip this event if it's not valid JSON
        }
    }
    
    /// Clear all callbacks after completion or error
    private func clearCallbacks() {
        self.onUpdateCallback = nil
        self.onCompleteCallback = nil
        self.onStructuredUpdateCallback = nil
        self.onErrorCallback = nil
    }
    
    /// Generate the request body for the API call with text only
    /// - Parameter prompt: The user's text prompt
    /// - Returns: Request body as dictionary
    private func generateRequestBody(prompt: String) -> [String: Any] {
        return [
            "contents": [
                [
                    "parts": [
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048, // Increased to ensure full responses
                "topP": 0.8,
                "topK": 10
            ]
        ]
    }
    
    /// Generate the request body for the API call with text and images
    /// - Parameters:
    ///   - prompt: The user's text prompt
    ///   - images: Array of images to include
    /// - Returns: Request body as dictionary
    private func generateRequestBodyWithImages(prompt: String, images: [NSImage]) -> [String: Any] {
        // If no images, use the simpler text-only body
        if images.isEmpty {
            return generateRequestBody(prompt: prompt)
        }
        
        // Create parts array with images and text
        var parts: [[String: Any]] = []
        
        // Add each image as an inline_data part
        for image in images {
            if let imageData = convertImageToBase64(image) {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData
                    ]
                ])
            }
        }
        
        // Add the text prompt as the final part
        parts.append([
            "text": prompt
        ])
        
        // Return the complete request body
        return [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048, // Increased to ensure full responses
                "topP": 0.8,
                "topK": 10
            ]
        ]
    }
    
    /// Convert an NSImage to a Base64 encoded string
    /// - Parameter image: The image to convert
    /// - Returns: Base64 encoded string or nil if conversion fails
    private func convertImageToBase64(_ image: NSImage) -> String? {
        // Create a JPEG representation of the image
        guard let imageData = image.jpegRepresentation(compressionFactor: 0.8) else {
            return nil
        }
        
        // Convert the data to Base64
        return imageData.base64EncodedString()
    }
}

// MARK: - URLSession Delegate

extension GeminiService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Append the new data to our buffer
        dataBuffer.append(data)
        
        // Convert to string to process SSE format
        guard let dataString = String(data: dataBuffer, encoding: .utf8) else {
            print("🔴 Failed to decode data as UTF-8")
            return
        }
        
        // Log data receipt
        print("🔵 Received data chunk: \(data.count) bytes")
        
        // Improved SSE parsing - use line-based approach instead of regex
        // Look for lines that start with "data:" and process them
        let lines = dataString.components(separatedBy: "\n")
        var processedUpTo = 0
        var currentEvent = ""
        
        for line in lines {
            // Check if this is the start of a new event
            if line.hasPrefix("data:") {
                // If we already have event data, process it first
                if !currentEvent.isEmpty {
                    processEvent(currentEvent.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentEvent = ""
                }
                
                // Extract data part (after "data:")
                let dataContent = line.dropFirst(5)
                currentEvent = String(dataContent)
            } 
            // Empty line marks end of an event
            else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !currentEvent.isEmpty {
                processEvent(currentEvent.trimmingCharacters(in: .whitespacesAndNewlines))
                currentEvent = ""
            }
            // Continuation of current event
            else if !currentEvent.isEmpty {
                currentEvent += "\n" + line
            }
            
            // Keep track of how much we've processed
            processedUpTo += line.utf8.count + 1 // +1 for the newline character
        }
        
        // If we have remaining data (incomplete event), keep it in the buffer
        if !currentEvent.isEmpty {
            dataBuffer = currentEvent.data(using: .utf8) ?? Data()
        } else if processedUpTo > 0 {
            // If we processed everything, clear the buffer
            dataBuffer = Data()
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Only call error callback if it's not due to explicit cancellation
            if (error as NSError).code != NSURLErrorCancelled {
                print("🔴 Stream error: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.isStreamActive = false
                    
                    // Provide structured content with the error if applicable
                    if let onStructuredUpdate = self.onStructuredUpdateCallback {
                        var content = self.contentBuilder.build()
                        content.errors.append(IdentifiableError(error))
                        content.finished = true
                        onStructuredUpdate(content)
                    }
                    
                    // Call the error callback if available
                    if let onError = self.onErrorCallback {
                        onError(error)
                    }
                    
                    // Clear callbacks to avoid memory leaks
                    self.clearCallbacks()
                }
            } else {
                print("🟠 Stream cancelled")
            }
        } else {
            // Before completing, check if there's any remaining data in the buffer to process
            if !dataBuffer.isEmpty {
                print("🟡 Processing remaining data in buffer on stream completion")
                if let remainingString = String(data: dataBuffer, encoding: .utf8) {
                    // Extract any data: sections from remaining buffer
                    let remaining = remainingString.split(separator: "data:")
                    for part in remaining {
                        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            processEvent(trimmed)
                        }
                    }
                }
            }
            
            if !fullText.isEmpty && isStreamActive {
                print("🟢 Stream completed without [DONE] marker, finalizing with content length: \(fullText.count)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.isStreamActive = false
                    
                    // Finalize structured content if applicable
                    if let onStructuredUpdate = self.onStructuredUpdateCallback {
                        var content = self.contentBuilder.build()
                        content.finished = true
                        onStructuredUpdate(content)
                    }
                    
                    // Call the traditional text completion callback if available
                    if let onComplete = self.onCompleteCallback {
                        onComplete(self.fullText)
                    }
                    
                    // Clear callbacks to avoid memory leaks
                    self.clearCallbacks()
                }
            }
        }
        
        // Reset buffer
        dataBuffer = Data()
    }
}

// MARK: - Error Handling

/// Custom errors for the Gemini service
enum GeminiError: Error, LocalizedError {
    /// API key is missing or empty
    case missingAPIKey
    
    /// The API URL could not be constructed
    case invalidURL
    
    /// No data was received from the API
    case noData
    
    /// The API response could not be parsed
    case invalidResponse
    
    /// The data format was invalid
    case invalidData
    
    /// Error descriptions
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key. Please enter your Gemini API key in Settings."
        case .invalidURL:
            return "The API URL could not be constructed."
        case .noData:
            return "No data was received from the API."
        case .invalidResponse:
            return "The API response could not be parsed."
        case .invalidData:
            return "The data format was invalid."
        }
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    /// Convert NSImage to JPEG data with specified compression
    /// - Parameter compressionFactor: Compression quality (0.0-1.0)
    /// - Returns: JPEG data or nil if conversion fails
    func jpegRepresentation(compressionFactor: CGFloat) -> Data? {
        let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let imageRep = cgImage else { return nil }
        
        let bitmap = NSBitmapImageRep(cgImage: imageRep)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
} 
