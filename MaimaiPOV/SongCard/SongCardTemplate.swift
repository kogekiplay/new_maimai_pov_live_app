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
  .card-container {
    width: 240px;
  }
  .card {
    width: 240px;
    position: relative;
    border-radius: 18px;
    padding: 4px;
    overflow: visible;
  }
  .card-body {
    background: #111;
    border-radius: 14px;
    overflow: hidden;
    position: relative;
  }
  .diff-basic { background: linear-gradient(135deg, #22bb5b, #18a04a); }
  .diff-advanced { background: linear-gradient(135deg, #fb9c2c, #e08520); }
  .diff-expert { background: linear-gradient(135deg, #f64861, #d93d53); }
  .diff-master { background: linear-gradient(135deg, #9e45e0, #8538c4); }
  .diff-remaster { background: linear-gradient(135deg, #dbaaff, #f6b2ff, #dbaaff); }
  .diff-utage { background: linear-gradient(135deg, #ff69b4, #e0559d); }
  .header-bar {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    padding: 3px 6px 0;
    position: relative;
    z-index: 2;
  }
  .difficulty-badge {
    font-size: 25px;
    font-weight: 900;
    color: white;
    letter-spacing: 1.5px;
    line-height: 1;
    -webkit-text-stroke: 1.2px rgba(0,0,0,0.5);
    paint-order: stroke fill;
    text-shadow: 0 2px 8px rgba(0,0,0,0.7), 0 0 16px rgba(0,0,0,0.3);
    transform: translateY(-2px);
  }
  .level-badge {
    color: white;
    line-height: 1;
    transform: translateY(-2px);
    display: flex;
    align-items: baseline;
    gap: 0;
    -webkit-text-stroke: 0.8px rgba(0,0,0,0.4);
    paint-order: stroke fill;
    text-shadow: 0 2px 8px rgba(0,0,0,0.65), 0 0 14px rgba(0,0,0,0.25);
  }
  .level-lv { font-size: 14px; font-weight: 800; }
  .level-num { font-size: 25px; font-weight: 900; }
  .level-dec { font-size: 18px; font-weight: 700; }
  .cover-area {
    padding: 0 6px 2px;
    position: relative;
    z-index: 1;
  }
  .cover-wrapper {
    width: 100%;
    aspect-ratio: 1 / 1;
    border-radius: 8px;
    overflow: hidden;
    border: 2px solid rgba(255,255,255,0.08);
  }
  .cover {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .cover-placeholder {
    width: 100%;
    height: 100%;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 50%, #f093fb 100%);
  }
  .info-bar {
    padding: 5px 8px 7px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .song-name {
    color: #fff;
    font-size: 25px;
    font-weight: 800;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    letter-spacing: 0.5px;
  }
  .meta-row {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 6px;
  }
  .chart-badge {
    font-size: 11px;
    font-weight: 800;
    padding: 2px 7px;
    border-radius: 4px;
    color: white;
    letter-spacing: 0.8px;
    flex-shrink: 0;
  }
  .chart-standard { background: rgba(255,255,255,0.12); }
  .chart-dx { background: rgba(255,80,80,0.55); }
  .chart-utage { background: rgba(255,105,180,0.55); }
  .requester-label {
    color: #ffd93d;
    font-size: 20px;
    font-weight: 800;
    text-shadow: 0 1px 4px rgba(0,0,0,0.4);
  }
</style>
</head>
<body>
<div class="card-container">
  <div class="card {{DIFF_CLASS}}">
    <div class="card-body">
      <div class="header-bar">
        <span class="difficulty-badge">{{DIFFICULTY}}</span>
        <span class="level-badge"><span class="level-lv">LV</span><span class="level-num">{{LEVEL_INT}}</span><span class="level-dec">{{LEVEL_DEC}}</span></span>
      </div>
      <div class="cover-area">
        {{COVER_HTML}}
      </div>
      <div class="info-bar">
        <div class="song-name">{{SONG_NAME}}</div>
        <div class="meta-row">
          <span class="chart-badge {{CHART_CLASS}}">{{CHART_TYPE}}</span>
          <span class="requester-label">{{REQUESTER}}</span>
        </div>
      </div>
    </div>
  </div>
</div>
</body>
</html>
"""

    static func render(data: SongCardData, coverBase64: String? = nil) -> String {
        let diffClass = diffClass(data.difficulty)
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

        let (levelInt, levelDec) = splitLevel(data.level?.htmlEscaped ?? "")
        let requesterText = data.requester.map { "by \($0.htmlEscaped)" } ?? ""

        return defaultHTML
            .replacingOccurrences(of: "{{DIFF_CLASS}}", with: diffClass)
            .replacingOccurrences(of: "{{DIFFICULTY}}", with: data.difficulty?.htmlEscaped ?? "")
            .replacingOccurrences(of: "{{LEVEL_INT}}", with: levelInt)
            .replacingOccurrences(of: "{{LEVEL_DEC}}", with: levelDec)
            .replacingOccurrences(of: "{{SONG_NAME}}", with: data.songName.htmlEscaped)
            .replacingOccurrences(of: "{{CHART_CLASS}}", with: chartClass)
            .replacingOccurrences(of: "{{CHART_TYPE}}", with: chartType)
            .replacingOccurrences(of: "{{REQUESTER}}", with: requesterText)
            .replacingOccurrences(of: "{{COVER_HTML}}", with: coverHTML)
            .replacingOccurrences(of: "{{ARTIST}}", with: data.artist.htmlEscaped)
            .replacingOccurrences(of: "{{COVER_URL}}", with: data.coverURL?.htmlEscaped ?? "")
    }

    private static func splitLevel(_ level: String) -> (intPart: String, decPart: String) {
        let parts = level.split(separator: ".", maxSplits: 1)
        let intPart = parts.first.map(String.init) ?? "0"
        let decPart = parts.count > 1 ? ".\(parts[1])" : ""
        return (intPart, decPart)
    }

    private static func diffClass(_ difficulty: String?) -> String {
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
        case "dx": return "chart-dx"
        case "utage": return "chart-utage"
        default: return "chart-standard"
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
