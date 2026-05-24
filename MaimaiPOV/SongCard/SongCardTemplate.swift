import Foundation

struct SongCardTemplate {
    static let defaultHTML = """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=240, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: transparent;
    font-family: -apple-system, sans-serif;
    width: 240px;
    height: 360px;
    overflow: hidden;
  }
  .card {
    background: rgba(0, 0, 0, 0.80);
    border-radius: 16px;
    padding: 10px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    border: 1px solid rgba(255, 255, 255, 0.12);
    width: 240px;
    height: 360px;
    position: relative;
    overflow: hidden;
  }
  .diff-bar {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 6px;
    border-radius: 16px 0 0 16px;
  }
  .diff-basic { background: #22bb5b; }
  .diff-advanced { background: #fb9c2c; }
  .diff-expert { background: #f64861; }
  .diff-master { background: #9e45e0; }
  .diff-remaster { background: linear-gradient(180deg, #dbaaff 0%, #f6b2ff 50%, #dbaaff 100%); }
  .diff-utage { background: #ff69b4; }
  .cover-wrapper {
    width: 200px;
    height: 200px;
    border-radius: 12px;
    flex-shrink: 0;
    overflow: hidden;
    position: relative;
  }
  .cover {
    width: 200px;
    height: 200px;
    border-radius: 12px;
    object-fit: cover;
  }
  .cover-placeholder {
    width: 200px;
    height: 200px;
    border-radius: 12px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  }
  .info {
    flex: 1;
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 3px;
    padding: 0 8px;
  }
  .song-name {
    color: white;
    font-size: 16px;
    font-weight: bold;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 210px;
  }
  .badges {
    display: flex;
    gap: 6px;
    align-items: center;
  }
  .badge {
    font-size: 11px;
    font-weight: bold;
    padding: 2px 8px;
    border-radius: 4px;
    color: white;
  }
  .badge-diff { background: rgba(255,255,255,0.15); }
  .badge-chart { background: rgba(255,255,255,0.1); }
  .badge-chart-dx { background: rgba(255,80,80,0.6); }
  .badge-chart-utage { background: rgba(255,105,180,0.6); }
  .level {
    color: #ffd93d;
    font-size: 14px;
    font-weight: bold;
  }
  .requester {
    color: rgba(255, 255, 255, 0.45);
    font-size: 11px;
  }
</style>
</head>
<body>
  <div class="card">
    <div class="diff-bar {{DIFF_CLASS}}"></div>
    {{COVER_HTML}}
    <div class="info">
      <div class="song-name">{{SONG_NAME}}</div>
      <div class="badges">
        <span class="badge badge-diff">{{DIFFICULTY}}</span>
        <span class="badge {{CHART_CLASS}}">{{CHART_TYPE}}</span>
      </div>
      <div class="level">Lv. {{LEVEL}}</div>
      <div class="requester">点歌: {{REQUESTER}}</div>
    </div>
  </div>
</body>
</html>
"""

    static func render(data: SongCardData, coverBase64: String? = nil) -> String {
        let diffClass = diffBarClass(data.difficulty)
        let chartClass = chartBadgeClass(data.chartType)
        let chartType = chartTypeDisplay(data.chartType)

        let coverHTML: String
        if let base64 = coverBase64 {
            coverHTML = """
            <div class="cover-wrapper">
              <img class="cover" src="data:image/jpeg;base64,\(base64)" alt="cover">
            </div>
            """
        } else {
            coverHTML = """
            <div class="cover-wrapper">
              <div class="cover-placeholder"></div>
            </div>
            """
        }

        return defaultHTML
            .replacingOccurrences(of: "{{SONG_NAME}}", with: data.songName)
            .replacingOccurrences(of: "{{ARTIST}}", with: data.artist)
            .replacingOccurrences(of: "{{DIFFICULTY}}", with: data.difficulty ?? "")
            .replacingOccurrences(of: "{{LEVEL}}", with: data.level ?? "")
            .replacingOccurrences(of: "{{REQUESTER}}", with: data.requester ?? "")
            .replacingOccurrences(of: "{{COVER_URL}}", with: data.coverURL ?? "")
            .replacingOccurrences(of: "{{DIFF_CLASS}}", with: diffClass)
            .replacingOccurrences(of: "{{CHART_CLASS}}", with: chartClass)
            .replacingOccurrences(of: "{{CHART_TYPE}}", with: chartType)
            .replacingOccurrences(of: "{{COVER_HTML}}", with: coverHTML)
    }

    private static func diffBarClass(_ difficulty: String?) -> String {
        guard let diff = difficulty?.lowercased() else { return "diff-master" }
        if diff.contains("basic") { return "diff-basic" }
        if diff.contains("advanced") { return "diff-advanced" }
        if diff.contains("expert") { return "diff-expert" }
        if diff.contains("remaster") || diff.contains("re:master") { return "diff-remaster" }
        if diff.contains("utage") { return "diff-utage" }
        return "diff-master"
    }

    private static func chartBadgeClass(_ chartType: String?) -> String {
        switch chartType {
        case "dx": return "badge badge-chart-dx"
        case "utage": return "badge badge-chart-utage"
        default: return "badge badge-chart"
        }
    }

    private static func chartTypeDisplay(_ chartType: String?) -> String {
        switch chartType {
        case "standard": return "STD"
        case "dx": return "DX"
        case "utage": return "UTAGE"
        default: return ""
        }
    }
}
