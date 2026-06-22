import Foundation

struct LinkToken: Hashable {
    let token: String
    let url: String
}

enum LinkPreviewAIContext {
    static func block(for text: String) async -> String? {
        var chunks: [String] = []
        for url in urls(in: text).prefix(4) {
            if isTweet(url), let chunk = try? await tweetChunk(for: url) {
                chunks.append(chunk)
            } else if isGitHub(url), let chunk = try? await githubChunk(for: url) {
                chunks.append(chunk)
            }
        }
        guard !chunks.isEmpty else { return nil }
        return chunks.joined(separator: "\n\n")
    }

    static func extractTokens(from text: String) -> [LinkToken] {
        urls(in: text).enumerated().map { index, url in
            LinkToken(token: "[[LINK:\(index)]]", url: url.absoluteString)
        }
    }

    static func tokenize(text: String, tokens: [LinkToken]) -> String {
        var output = text
        for token in tokens {
            output = output.replacingOccurrences(of: token.url, with: token.token)
        }
        return output
    }

    static func restoreAndEnsure(markdown: String, tokens: [LinkToken]) -> String {
        guard !tokens.isEmpty else { return markdown }
        var output = markdown
        for token in tokens {
            output = output.replacingOccurrences(of: token.token, with: token.url)
        }
        let missing = tokens.map(\.url).filter { !output.contains($0) }
        guard !missing.isEmpty else { return output }
        let suffix = "## 链接\n" + missing.joined(separator: "\n")
        return output.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + suffix
    }

    private static func urls(in text: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>\]\)"']+"#, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let raw = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"'"))
            guard let url = URL(string: raw), seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    private static func isTweet(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host) else {
            return false
        }
        let parts = url.pathComponents.map { $0.lowercased() }
        return parts.contains("status") || parts.contains("statuses")
    }

    private static func isGitHub(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "www.github.com"
    }

    private static func tweetChunk(for url: URL) async throws -> String {
        var components = URLComponents(string: "https://publish.twitter.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "omit_script", value: "true"),
            URLQueryItem(name: "url", value: url.absoluteString)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let payload = try JSONDecoder().decode(TweetOEmbed.self, from: data)
        let text = plainText(fromHTML: payload.html ?? "").prefix(900)
        return """
        - X: \(payload.author_name ?? url.absoluteString)
          URL: \(url.absoluteString)
          内容: \(text)
        """
    }

    private static func githubChunk(for url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""
        let title = metaContent("og:title", in: html) ?? htmlTitle(in: html) ?? url.absoluteString
        let description = metaContent("og:description", in: html) ?? ""
        return """
        - GitHub: \(title)
          URL: \(url.absoluteString)
          描述: \(description)
        """
    }

    private static func plainText(fromHTML html: String) -> String {
        html
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .decodedHTMLEntities
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func metaContent(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<meta\b(?=[^>]*(?:property|name)=["']"# + escaped + #"["'])(?=[^>]*content=["']([^"']*)["'])[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return (html as NSString).substring(with: match.range(at: 1)).decodedHTMLEntities
    }

    private static func htmlTitle(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return plainText(fromHTML: (html as NSString).substring(with: match.range(at: 1)))
    }
}

private struct TweetOEmbed: Decodable {
    let author_name: String?
    let html: String?
}

private extension String {
    var decodedHTMLEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
