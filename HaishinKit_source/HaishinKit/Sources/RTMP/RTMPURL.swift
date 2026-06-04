import Foundation

struct RTMPURL {
    let url: URL

    var streamName: String {
        var pathComponents = url.pathComponents
        pathComponents.removeFirst()
        pathComponents.removeFirst()
        return pathComponents.joined(separator: "/")
    }

    var command: String {
        let target = "/" + streamName
        let urlString = url.absoluteString
        guard let range = urlString.range(of: target) else {
            return urlString
        }
        return urlString.replacingOccurrences(of: target, with: "", options: [], range: range)
    }

    init(url: URL) {
        self.url = url
    }
}
