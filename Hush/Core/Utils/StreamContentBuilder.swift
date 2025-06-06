import Foundation
import SwiftUI
import Combine

/// Processes streaming content into structured StreamContent
class StreamContentBuilder {
    // MARK: - Properties
    
    /// Raw text buffer containing the current streaming content
    private var buffer: String
    
    /// JSON decoder with date formatting configuration
    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }()
    
    // MARK: - Initialization
    
    /// Create a new builder with the provided buffer
    init(buffer: String = "") {
        self.buffer = buffer
    }
    
    // MARK: - Public Methods
    
    /// Process raw input into structured content
    func build() -> StreamContent {
        print("🔄 Processing \(buffer.count) characters of content")
        
        // Parse raw content first and provide markdown and XML blocks
        let raw = parseRawContent()
        
        // Create a hierarchical ID generator
        var ids: any IdentifierGenerator = IncrementalIdentifierGenerator.create()
        
        // Run through the transformation pipeline
        var content = buildBasicContent(raw: raw, ids: ids.nested())
        content = applyOptionBuilder(input: content, ids: ids.nested())
        content = applyWidgetBuilder(input: content, ids: ids.nested())
        content = applyQuestionBuilder(input: content, ids: ids.nested())
        
        return content
    }
    
    // MARK: - Private Methods
    
    /// Parse raw content into basic blocks (text and XML)
    private func parseRawContent() -> [ContentBlock] {
        var results = [ContentBlock]()
        var remaining = buffer
        
        // Simple XML tag detection (not handling self-closing tags properly)
        // In production, you'd use more robust parsing
        while !remaining.isEmpty {
            // Look for start of XML tag
            if let match = remaining.range(of: "<(Safe[A-Za-z]+)\\b", options: .regularExpression) {
                let tagName = String(remaining[match]).dropFirst().trimmingCharacters(in: .whitespaces)
                
                // Extract text before tag as markdown
                let markdownText = String(remaining[..<match.lowerBound])
                if !markdownText.isEmpty {
                    results.append(.markdown(markdownText))
                }
                
                // Look for matching end tag
                let endTagPattern = "</\(tagName)>"
                if let endMatch = remaining.range(of: endTagPattern) {
                    // Extract everything between tags (including tags)
                    let xmlBlock = String(remaining[match.lowerBound..<endMatch.upperBound])
                    results.append(.xml(xmlBlock))
                    
                    // Continue with remainder
                    if endMatch.upperBound < remaining.endIndex {
                        remaining = String(remaining[endMatch.upperBound...])
                    } else {
                        remaining = ""
                    }
                } else {
                    // No closing tag found, treat as incomplete XML
                    results.append(.markdown(String(remaining[..<match.lowerBound])))
                    remaining = String(remaining[match.lowerBound...])
                    break
                }
            } else {
                // No XML tags found, treat all as markdown
                results.append(.markdown(remaining))
                remaining = ""
            }
        }
        
        return results
    }
    
    /// Build basic content from raw blocks
    private func buildBasicContent(raw: [ContentBlock], ids: IdentifierGenerator) -> StreamContent {
        var content = StreamContent()
        var idGen = ids
        
        for block in raw {
            switch block {
            case .markdown(let text):
                // Process markdown content, removing trailing partial tables
                var cleanedText = text
                if let lastLineRange = text.range(of: "\\|[^\\n]*$", options: .regularExpression) {
                    // Remove last line if it looks like a partial table row
                    cleanedText = String(text[..<lastLineRange.lowerBound])
                }
                
                // Parse tables
                let (markdownContent, tables) = parseMarkdownTables(cleanedText)
                
                // Add remaining markdown content if not empty
                if !markdownContent.isEmpty {
                    content.items.append(.init(ids: &idGen, value: .markdown(MarkdownEntry(content: markdownContent))))
                }
                
                // Add parsed tables
                for table in tables {
                    content.items.append(.init(ids: &idGen, value: .markdownTable(table)))
                }
                
            case .xml(let xmlText):
                // Parse XML content
                if let element = parseXML(xmlText) {
                    content.items.append(.init(ids: &idGen, value: .xml([element])))
                }
            }
        }
        
        return content
    }
    
    /// Parse markdown tables from text
    private func parseMarkdownTables(_ text: String) -> (String, [MarkdownTable]) {
        var result = text
        var tables: [MarkdownTable] = []
        
        // Simple table detection (in production, use a proper markdown parser)
        let tablePattern = "\\|[^\\n]+\\|\\n\\|[-:\\|\\s]+\\|\\n(?:\\|[^\\n]+\\|\\n)+"
        
        let regex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(text.startIndex..., in: text)
        
        if let regex = regex, let match = regex.firstMatch(in: text, options: [], range: range) {
            // Extract the table
            if let tableRange = Range(match.range, in: text) {
                let tableText = String(text[tableRange])
                
                // Parse the table structure
                let rows = tableText.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                
                if rows.count >= 2 {
                    // Parse headers
                    let headerRow = rows[0]
                    let headers = headerRow.components(separatedBy: "|")
                        .filter { !$0.isEmpty }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    
                    // Skip separator row
                    
                    // Parse data rows
                    var dataRows: [[String]] = []
                    for i in 2..<rows.count {
                        let rowCells = rows[i].components(separatedBy: "|")
                            .filter { !$0.isEmpty }
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        
                        if !rowCells.isEmpty {
                            dataRows.append(rowCells)
                        }
                    }
                    
                    // Create table model
                    let table = MarkdownTable(headers: headers, rows: dataRows)
                    tables.append(table)
                    
                    // Remove the table from markdown content
                    result = text.replacingCharacters(in: tableRange, with: "")
                }
            }
        }
        
        return (result, tables)
    }
    
    /// Parse XML string into XMLElement structure
    private func parseXML(_ xmlString: String) -> XMLElement? {
        // In a production app, use XMLParser properly
        // This is a simplified version that just extracts basic info
        
        let tagPattern = "<(\\w+)([^>]*)>([\\s\\S]*?)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern),
              let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
              let tagNameRange = Range(match.range(at: 1), in: xmlString),
              let attributesRange = Range(match.range(at: 2), in: xmlString),
              let contentRange = Range(match.range(at: 3), in: xmlString) else {
            return nil
        }
        
        let tagName = String(xmlString[tagNameRange])
        let attributesText = String(xmlString[attributesRange])
        let content = String(xmlString[contentRange])
        
        // Parse attributes
        var attributes = [String: String]()
        let attrPattern = "(\\w+)=[\"'](.*?)[\"']"
        if let attrRegex = try? NSRegularExpression(pattern: attrPattern) {
            let attrMatches = attrRegex.matches(in: attributesText, range: NSRange(attributesText.startIndex..., in: attributesText))
            
            for match in attrMatches {
                if let nameRange = Range(match.range(at: 1), in: attributesText),
                   let valueRange = Range(match.range(at: 2), in: attributesText) {
                    let name = String(attributesText[nameRange])
                    let value = String(attributesText[valueRange])
                    attributes[name] = value
                }
            }
        }
        
        // For simplicity, we're not parsing nested elements in this example
        return XMLElement(name: tagName, attributes: attributes, text: content, children: [])
    }
    
    /// Apply option builder to process layout options
    private func applyOptionBuilder(input: StreamContent, ids: IdentifierGenerator) -> StreamContent {
        var result = input
        
        // Process items to extract layout options
        for (index, item) in input.items.enumerated() {
            if case .xml(let elements) = item.value {
                for element in elements {
                    if element.name == "SafeOption" {
                        // Parse layout options
                        if let name = element.attributes["name"], name == "page.control",
                           let value = element.attributes["value"] {
                            switch value {
                            case "submit":
                                result.options.page.control = .submit
                            case "back":
                                result.options.page.control = .back
                            case "next":
                                result.options.page.control = .next
                            default:
                                result.options.page.control = .none
                            }
                            
                            // Remove the option from items
                            result.items.remove(at: index)
                            break
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    /// Apply widget builder to process widgets
    private func applyWidgetBuilder(input: StreamContent, ids: IdentifierGenerator) -> StreamContent {
        var result = input
        var idGen = ids
        var indicesToRemove = [Int]()
        var widgetsToAdd = [StreamContent.Item]()
        
        // Find potential container widgets
        for (index, item) in input.items.enumerated() {
            if case .xml(let elements) = item.value {
                for element in elements {
                    if element.name == "SafeContainer" {
                        // Create container widget
                        var container = ContainerWidget()
                        
                        // Check if previous item is a markdown heading to use as title
                        if index > 0, case .markdown(let entry) = result.items[index-1].value {
                            // Extract heading (simple implementation)
                            if let headingRange = entry.content.range(of: "###\\s+(.+)$", options: .regularExpression) {
                                let heading = String(entry.content[headingRange])
                                    .replacingOccurrences(of: "###\\s+", with: "", options: .regularExpression)
                                container.title = heading
                                
                                // Remove the heading
                                indicesToRemove.append(index-1)
                            }
                        }
                        
                        // Add container
                        widgetsToAdd.append(.init(ids: &idGen, value: .container(container)))
                        indicesToRemove.append(index)
                        
                    } else if element.name == "SafeViz" {
                        // Process visualization widgets
                        if let name = element.attributes["name"] {
                            if name == "TREND" {
                                // Parse trend data from widget summary
                                if let jsonText = element.text {
                                    do {
                                        // Complete partial JSON if needed
                                        let completedJson = completePartialJSON(jsonText)
                                        let data = completedJson.data(using: .utf8)!
                                        let widget = try Self.jsonDecoder.decode(TrendWidget.self, from: data)
                                        
                                        // Add widget
                                        widgetsToAdd.append(.init(ids: &idGen, value: .widget(.trend(widget))))
                                        indicesToRemove.append(index)
                                    } catch {
                                        print("Error parsing trend widget: \(error)")
                                        result.errors.append(IdentifiableError(error))
                                    }
                                }
                            } else if name == "CHART" {
                                // Parse chart data
                                if let jsonText = element.text {
                                    do {
                                        // Complete partial JSON if needed
                                        let completedJson = completePartialJSON(jsonText)
                                        let data = completedJson.data(using: .utf8)!
                                        let widget = try Self.jsonDecoder.decode(ChartWidget.self, from: data)
                                        
                                        // Add widget
                                        widgetsToAdd.append(.init(ids: &idGen, value: .widget(.chart(widget))))
                                        indicesToRemove.append(index)
                                    } catch {
                                        print("Error parsing chart widget: \(error)")
                                        result.errors.append(IdentifiableError(error))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Remove processed items (in reverse order to maintain indices)
        for index in indicesToRemove.sorted(by: >) {
            if index < result.items.count {
                result.items.remove(at: index)
            }
        }
        
        // Add new widgets
        result.items.append(contentsOf: widgetsToAdd)
        
        return result
    }
    
    /// Apply question builder to process questions
    private func applyQuestionBuilder(input: StreamContent, ids: IdentifierGenerator) -> StreamContent {
        var result = input
        var idGen = ids
        var indicesToRemove = [Int]()
        var questionsToAdd = [StreamContent.Item]()
        var pendingQuestions = [Question]()
        
        // Process questions
        for (index, item) in input.items.enumerated() {
            if case .xml(let elements) = item.value {
                for element in elements {
                    if element.name == "SafeQuestion" {
                        // Create question
                        let questionText = element.text ?? "Missing question"
                        var question = Question(text: questionText)
                        
                        // Extract options if available
                        for child in element.children {
                            if child.name == "SafeOption" {
                                if let optionText = child.text {
                                    question.options.append(optionText)
                                }
                            }
                        }
                        
                        // Add to pending questions for potential grouping
                        pendingQuestions.append(question)
                        indicesToRemove.append(index)
                    }
                }
            }
        }
        
        // Group questions if there are multiple
        if pendingQuestions.count > 1 {
            // Create question group
            let group = QuestionGroup(title: nil, questions: pendingQuestions)
            questionsToAdd.append(.init(ids: &idGen, value: .questionGroup(group)))
        } else if pendingQuestions.count == 1 {
            // Add single question
            questionsToAdd.append(.init(ids: &idGen, value: .question(pendingQuestions[0])))
        }
        
        // Remove processed items (in reverse order to maintain indices)
        for index in indicesToRemove.sorted(by: >) {
            if index < result.items.count {
                result.items.remove(at: index)
            }
        }
        
        // Add new questions
        result.items.append(contentsOf: questionsToAdd)
        
        return result
    }
    
    /// Complete partial JSON by adding missing closing characters
    private func completePartialJSON(_ json: String) -> String {
        // Simple completion - adds any missing closing braces, brackets, or quotes
        var result = json
        var openBraces = 0
        var openBrackets = 0
        var openQuotes = false
        
        for char in result {
            switch char {
            case "{":
                openBraces += 1
            case "}":
                openBraces -= 1
            case "[":
                openBrackets += 1
            case "]":
                openBrackets -= 1
            case "\"":
                // Toggle quote state (ignoring escaped quotes)
                if result.last != "\\" {
                    openQuotes.toggle()
                }
            default:
                break
            }
        }
        
        // Close any open quotes
        if openQuotes {
            result += "\""
        }
        
        // Close any open brackets
        result += String(repeating: "]", count: max(0, openBrackets))
        
        // Close any open braces
        result += String(repeating: "}", count: max(0, openBraces))
        
        return result
    }
}

/// Represents a block of raw content
enum ContentBlock {
    /// Markdown text content
    case markdown(String)
    
    /// XML content
    case xml(String)
} 
