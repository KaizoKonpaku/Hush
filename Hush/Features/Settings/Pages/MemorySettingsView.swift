import SwiftUI

extension MainWindowView {
    var memorySettings: some View {
        Form {
            Section {
                explainedPicker(
                    "Keep history",
                    description: "How long conversations are stored.",
                    selection: $memoryKeepHistory
                ) {
                    Text("Off").tag("off")
                    Text("Session only").tag("session")
                    Text("7 days").tag("week")
                    Text("30 days").tag("month")
                    Text("Forever").tag("forever")
                }
                explainedToggle(
                    "Auto-include history in context",
                    description: "Adds recent messages automatically to prompts when useful.",
                    isOn: $memoryAutoIncludeContext
                )
            } header: {
                Text("History")
            } footer: {
                Text("Keep recent context available without making the page feel like storage settings.")
            }

            Section {
                explainedToggle(
                    "Enable long-term memory",
                    description: "Lets HUSH save reusable long-term facts.",
                    isOn: $memoryLongTermEnabled
                )
                if memoryLongTermEnabled {
                    explainedPicker(
                        "Scope",
                        description: "Where long-term memories are shared.",
                        selection: $memoryLongTermScope
                    ) {
                        Text("Global").tag("global")
                        Text("Per-app").tag("perapp")
                        Text("Per-project").tag("perproject")
                    }
                }
            } header: {
                Text("Memory")
            } footer: {
                Text("Use long-term memory only when reusable facts are worth keeping around.")
            }

            Section {
                explainedToggle(
                    "Autosave transcripts",
                    description: "Saves chat transcripts automatically.",
                    isOn: $memoryAutosaveTranscripts
                )
                if memoryAutosaveTranscripts {
                    explainedPicker(
                        "Transcript format",
                        description: "File format used for saved transcripts.",
                        selection: $memoryTranscriptFormat
                    ) {
                        Text("Markdown").tag("markdown")
                        Text("Plain text").tag("plain")
                        Text("JSON").tag("json")
                    }
                    explainedToggle(
                        "Include metadata",
                        description: "Adds timestamps, model, and context info.",
                        isOn: $memoryIncludeMetadata
                    )
                }
                explainedToggle(
                    "Auto-name sessions",
                    description: "Generates titles from conversation content.",
                    isOn: $memoryAutoNameSessions
                )
            } header: {
                Text("Transcripts")
            } footer: {
                Text("Saved transcripts should stay readable, lightweight, and easy to reuse later.")
            }
        }
        .settingsPageLayout()
    }
}
