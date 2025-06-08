import SwiftUI

/// Main view for rendering streaming content
struct StreamContentView: View {
    /// The content to render
    let content: StreamContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(content.items) { item in
                switch item.value {
                case .markdown(let entry):
                    MarkdownEntryView(entry: entry)
                        .id(item.id)
                
                case .markdownTable(let table):
                    MarkdownTableView(table: table)
                        .id(item.id)
                
                case .question(let question):
                    QuestionView(question: question)
                        .id(item.id)
                
                case .questionGroup(let group):
                    QuestionGroupView(group: group)
                        .id(item.id)
                
                case .widget(let widget):
                    WidgetView(widget: widget)
                        .id(item.id)
                
                case .container(let container):
                    ContainerWidgetView(container: container)
                        .id(item.id)
                
                case .input(let input):
                    InputView(input: input)
                        .id(item.id)
                
                case .xml:
                    // XML is not rendered directly
                    EmptyView()
                }
            }
            
            // Display errors if any
            ForEach(content.errors) { error in
                Text("Error: \(error.error.localizedDescription)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Show page controls if configured
            switch content.options.page.control {
            case .submit:
                PageControlButton(
                    systemName: "square.and.pencil.circle.fill",
                    label: "Submit",
                    action: { /* Handle submission */ }
                )
            case .next:
                PageControlButton(
                    systemName: "arrow.right.circle.fill",
                    label: "Next",
                    action: { /* Handle next */ }
                )
            case .back:
                PageControlButton(
                    systemName: "arrow.left.circle.fill",
                    label: "Back",
                    action: { /* Handle back */ }
                )
            case .none:
                EmptyView()
            }
        }
        .padding()
    }
}

/// View for displaying markdown content
struct MarkdownEntryView: View {
    /// The markdown entry to render
    let entry: MarkdownEntry
    
    /// Whether the content is expanded
    @State private var expanded = true
    
    var body: some View {
        VStack(alignment: .leading) {
            // Process the content to handle code blocks
            let processedContent = processCodeBlocks(expanded ? entry.content : (entry.collapsed ?? entry.content))
            
            // Use SwiftUI's built-in markdown support with processed content
            Text(LocalizedStringKey(processedContent))
                .textSelection(.enabled)
            
            // Show expand/collapse button if collapsible
            if entry.collapsible {
                Button(expanded ? "Show Less" : "Show More") {
                    withAnimation {
                        expanded.toggle()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
    }
    
    /// Process code blocks to ensure proper formatting
    private func processCodeBlocks(_ content: String) -> String {
        var result = content
        
        // Pattern to match code blocks (```language\ncode\n```)
        let codeBlockPattern = "```(\\w*)\\n([\\s\\S]*?)```"
        
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)
            
            // Process matches in reverse to maintain indices
            for match in matches.reversed() {
                if let codeBlockRange = Range(match.range, in: result),
                   let _ = Range(match.range(at: 1), in: result),
                   let codeRange = Range(match.range(at: 2), in: result) {
                    
                    let code = String(result[codeRange])
                    
                    // Add proper line breaks and formatting
                    let formattedCode = code
                        .components(separatedBy: .newlines)
                        .map { "    " + $0 } // Add 4 spaces for indentation
                        .joined(separator: "\n")
                    
                    // Replace the code block with formatted version
                    result.replaceSubrange(codeBlockRange, with: "\n\n\(formattedCode)\n\n")
                }
            }
        }
        
        return result
    }
}

/// View for displaying markdown tables
struct MarkdownTableView: View {
    /// The table data to render
    let table: MarkdownTable
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(table.headers, id: \.self) { header in
                    TableCell(text: header, isHeader: true)
                }
            }
            .background(Color.gray.opacity(0.2))
            
            // Data rows
            ForEach(table.rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(0..<min(table.headers.count, table.rows[rowIndex].count), id: \.self) { colIndex in
                        TableCell(text: table.rows[rowIndex][colIndex], isHeader: false)
                    }
                }
                .background(rowIndex % 2 == 0 ? Color.clear : Color.gray.opacity(0.1))
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

/// A cell in a markdown table
struct TableCell: View {
    /// The cell text
    let text: String
    
    /// Whether this is a header cell
    let isHeader: Bool
    
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(isHeader ? .headline : .body)
            .fontWeight(isHeader ? .bold : .regular)
            .padding(8)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .overlay(
                Rectangle()
                    .frame(width: 1, height: nil, alignment: .trailing)
                    .foregroundColor(Color.gray.opacity(0.3)),
                alignment: .trailing
            )
    }
}

/// View for displaying a question
struct QuestionView: View {
    /// The question to render
    let question: Question
    
    /// Currently selected option index
    @State private var selectedIndex: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.text)
                .font(.headline)
                .textSelection(.enabled)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(question.options.indices, id: \.self) { index in
                    Button(action: {
                        selectedIndex = index
                    }) {
                        HStack {
                            Image(systemName: selectedIndex == index ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedIndex == index ? .blue : .gray)
                            
                            Text(question.options[index])
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            selectedIndex = question.selectedIndex
        }
    }
}

/// View for displaying a group of questions
struct QuestionGroupView: View {
    /// The question group to render
    let group: QuestionGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Show group title if available
            if let title = group.title {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Display questions
            ForEach(group.questions.indices, id: \.self) { index in
                QuestionView(question: group.questions[index])
            }
        }
        .padding()
        .background(Color.blue.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }
}

/// View for displaying widgets
struct WidgetView: View {
    /// The widget to render
    let widget: Widget
    
    var body: some View {
        switch widget {
        case .trend(let trendWidget):
            TrendWidgetView(widget: trendWidget)
        case .chart(let chartWidget):
            ChartWidgetView(widget: chartWidget)
        }
    }
}

/// View for displaying trend visualization
struct TrendWidgetView: View {
    /// The trend data to render
    let widget: TrendWidget
    
    var body: some View {
        VStack(alignment: .leading) {
            if let title = widget.riskScenarioName {
                Text(title)
                    .font(.headline)
            }
            
            if let data = widget.trendData, !data.isEmpty {
                // Simple line graph representation
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<min(20, data.count), id: \.self) { index in
                        // Scale the bar relative to the maximum value
                        let height = (data[index].eventLikelihood ?? 0) * 100
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .green]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: max(10, height))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 100)
                .padding(.top)
            } else {
                Text("No trend data available")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}

/// View for displaying chart visualization
struct ChartWidgetView: View {
    /// The chart data to render
    let widget: ChartWidget
    
    var body: some View {
        VStack(alignment: .leading) {
            if let title = widget.title {
                Text(title)
                    .font(.headline)
            }
            
            if let series = widget.series, !series.isEmpty {
                // Simple chart representation
                VStack(alignment: .leading) {
                    ForEach(0..<min(5, series.count), id: \.self) { seriesIndex in
                        if let name = series[seriesIndex].name,
                           let data = series[seriesIndex].data,
                           !data.isEmpty {
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(seriesColor(index: seriesIndex))
                                    .frame(width: 12, height: 12)
                                
                                Text(name)
                                    .font(.caption)
                                
                                Spacer()
                                
                                Text(String(format: "%.1f", data.reduce(0, +) / Double(data.count)))
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
                .padding(.top)
            } else {
                Text("No chart data available")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
    
    /// Get color for series by index
    private func seriesColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .red, .orange, .purple]
        return colors[index % colors.count]
    }
}

/// View for displaying a widget container
struct ContainerWidgetView: View {
    /// The container widget to render
    let container: ContainerWidget
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show container title if available
            if let title = container.title {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Horizontal scrollable container for widgets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(container.widgets) { item in
                        // Only render widgets in containers
                        if case .widget(let widget) = item.value {
                            WidgetView(widget: widget)
                                .frame(width: 250)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

/// View for displaying input controls
struct InputView: View {
    /// The input to render
    let input: Input
    
    /// Current input value
    @State private var value: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(input.label)
                .font(.headline)
            
            switch input.type {
            case .text:
                TextField("", text: $value)
                    .frame(maxWidth: 100)
                
            case .number:
                TextField("", text: $value)
                    .frame(maxWidth: 100)
                
            case .date:
                DatePicker(
                    "Select \(input.label)",
                    selection: Binding(
                        get: {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            return formatter.date(from: value) ?? Date()
                        },
                        set: {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            value = formatter.string(from: $0)
                        }
                    ),
                    displayedComponents: .date
                )
            }
        }
        .onAppear {
            value = input.initialValue ?? ""
        }
    }
}

/// Button for page controls
struct PageControlButton: View {
    /// System image name
    let systemName: String
    
    /// Button label
    let label: String
    
    /// Button action
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemName)
                    .font(.largeTitle)
                
                Text(label)
                    .font(.headline)
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical)
    }
} 