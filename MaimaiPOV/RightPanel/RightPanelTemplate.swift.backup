import Foundation

struct RightPanelTemplate {
    static let rowWidth = 420
    static let rowHeight = 120
    static let titleWidth = 420
    static let titleHeight = 80

    static let titleHTML = """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=420, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: rgba(15,15,30,0.95);
    font-family: -apple-system, sans-serif;
    width: 420px;
    height: 80px;
    overflow: hidden;
  }
  .title-container {
    width: 420px;
    height: 80px;
    display: flex;
    align-items: center;
    padding: 0 20px;
    border-bottom: 1px solid rgba(255,255,255,0.1);
  }
  .title-icon {
    font-size: 24px;
    margin-right: 10px;
  }
  .title-text {
    color: rgba(255,255,255,0.85);
    font-size: 22px;
    font-weight: 700;
    letter-spacing: 1px;
  }
</style>
</head>
<body>
<div class="title-container">
  <span class="title-icon">🎵</span>
  <span class="title-text">点歌队列</span>
</div>
</body>
</html>
"""

    static let rowHTML = """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=420, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: transparent;
    font-family: -apple-system, sans-serif;
    width: 420px;
    height: 120px;
    overflow: hidden;
  }
  .row-container {
    width: 420px;
    height: 120px;
    display: flex;
    align-items: center;
    padding: 8px 12px;
    position: relative;
  }
  .row-body {
    width: 100%;
    height: 100%;
    background: rgba(26,26,46,0.9);
    border-radius: 10px;
    display: flex;
    align-items: center;
    padding: 10px 12px;
    position: relative;
    overflow: hidden;
  }
  .diff-bar {
    position: absolute;
    right: 0;
    top: 0;
    width: 4px;
    height: 100%;
    border-radius: 0 10px 10px 0;
  }
  .diff-bar-basic { background: linear-gradient(180deg, #22bb5b, #18a04a); }
  .diff-bar-advanced { background: linear-gradient(180deg, #fb9c2c, #e08520); }
  .diff-bar-expert { background: linear-gradient(180deg, #f64861, #d93d53); }
  .diff-bar-master { background: linear-gradient(180deg, #9e45e0, #8538c4); }
  .diff-bar-remaster { background: linear-gradient(180deg, #dbaaff, #f6b2ff); }
  .diff-bar-utage { background: linear-gradient(180deg, #ff69b4, #e0559d); }
  .cover-area {
    width: 80px;
    height: 80px;
    border-radius: 8px;
    overflow: hidden;
    flex-shrink: 0;
    border: 1px solid rgba(255,255,255,0.08);
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
  .info-area {
    flex: 1;
    margin-left: 12px;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 4px;
    overflow: hidden;
    padding-right: 8px;
  }
  .song-name {
    color: #fff;
    font-size: 18px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    letter-spacing: 0.3px;
  }
  .meta-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .chart-badge {
    font-size: 10px;
    font-weight: 800;
    padding: 1px 6px;
    border-radius: 3px;
    color: white;
    letter-spacing: 0.5px;
    flex-shrink: 0;
  }
  .chart-standard { background: rgba(255,255,255,0.12); }
  .chart-dx { background: rgba(255,80,80,0.55); }
  .chart-utage { background: rgba(255,105,180,0.55); }
  .level-text {
    color: rgba(255,255,255,0.7);
    font-size: 13px;
    font-weight: 600;
  }
  .bottom-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .gift-value {
    color: #FFD700;
    font-size: 12px;
    font-weight: 600;
  }
  .requester {
    color: rgba(255,255,255,0.45);
    font-size: 12px;
    font-weight: 500;
  }
</style>
</head>
<body>
<div class="row-container">
  <div class="row-body">
    <div class="diff-bar {{DIFF_BAR_CLASS}}"></div>
    <div class="cover-area">
      {{COVER_HTML}}
    </div>
    <div class="info-area">
      <div class="song-name">{{SONG_NAME}}</div>
      <div class="meta-row">
        <span class="chart-badge {{CHART_CLASS}}">{{CHART_TYPE}}</span>
        <span class="level-text">{{LEVEL}}</span>
      </div>
      <div class="bottom-row">
        {{GIFT_VALUE_HTML}}
        <span class="requester">{{REQUESTER}}</span>
      </div>
    </div>
  </div>
</div>
</body>
</html>
"""

    static func renderTitle() -> String {
        return titleHTML
    }

    static func renderRow(data: SongCardData, coverBase64: String? = nil) -> String {
        let diffBarClass = Self.diffBarClass(data.difficulty)
        let chartClass = Self.chartBadgeClass(data.chartType)
        let chartType = Self.chartTypeDisplay(data.chartType)
        let level = data.level ?? ""

        let coverHTML: String
        if let base64 = coverBase64 {
            coverHTML = """
            <img class="cover" src="data:image/jpeg;base64,\(base64)" alt="cover">
            """
        } else {
            coverHTML = """
            <div class="cover-placeholder"></div>
            """
        }

        let requesterText = data.requester.map { "by \($0)" } ?? ""
        let giftHTML = Self.giftValueHTML(data.giftValue)

        return rowHTML
            .replacingOccurrences(of: "{{DIFF_BAR_CLASS}}", with: diffBarClass)
            .replacingOccurrences(of: "{{COVER_HTML}}", with: coverHTML)
            .replacingOccurrences(of: "{{SONG_NAME}}", with: data.songName)
            .replacingOccurrences(of: "{{CHART_CLASS}}", with: chartClass)
            .replacingOccurrences(of: "{{CHART_TYPE}}", with: chartType)
            .replacingOccurrences(of: "{{LEVEL}}", with: level)
            .replacingOccurrences(of: "{{GIFT_VALUE_HTML}}", with: giftHTML)
            .replacingOccurrences(of: "{{REQUESTER}}", with: requesterText)
    }

    static func giftValueHTML(_ value: Int) -> String {
        if value <= 0 { return "" }
        let rmb = Double(value) / 1000.0
        return "<span class=\"gift-value\">🎁 ¥\(String(format: "%.2f", rmb))</span>"
    }

    private static func diffBarClass(_ difficulty: String?) -> String {
        guard let diff = difficulty?.lowercased() else { return "diff-bar-master" }
        if diff.contains("basic") { return "diff-bar-basic" }
        if diff.contains("advanced") { return "diff-bar-advanced" }
        if diff.contains("expert") { return "diff-bar-expert" }
        if diff.contains("remaster") || diff.contains("re:master") { return "diff-bar-remaster" }
        if diff.contains("utage") { return "diff-bar-utage" }
        return "diff-bar-master"
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
