import Foundation

struct OverlayResponseService {
    func makeResponse(for prompt: String, captureCount: Int) -> String {
        let textPart: String
        if prompt.isEmpty {
            textPart = "I analyzed the captured visuals and extracted the likely intent."
        } else {
            textPart = "For your request: \"\(prompt)\", here is a concise answer with actionable next steps."
        }

        let capturePart: String
        if captureCount > 0 {
            capturePart = " Included \(captureCount) capture\(captureCount == 1 ? "" : "s") as context."
        } else {
            capturePart = ""
        }

        return textPart + capturePart
    }
}
