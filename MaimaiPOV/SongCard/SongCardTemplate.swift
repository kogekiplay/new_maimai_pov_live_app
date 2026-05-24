import Foundation

struct SongCardTemplate {
    static let defaultHTML = """
<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: transparent;
    font-family: -apple-system, sans-serif;
    width: 200px;
    height: 300px;
    overflow: hidden;
  }
  .card {
    background: rgba(0, 0, 0, 0.75);
    border-radius: 16px;
    padding: 12px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    border: 1px solid rgba(255, 255, 255, 0.15);
    width: 200px;
    height: 300px;
  }
  .cover {
    width: 160px;
    height: 160px;
    border-radius: 12px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    flex-shrink: 0;
  }
  .info {
    flex: 1;
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
  }
  .song-name {
    color: white;
    font-size: 16px;
    font-weight: bold;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 170px;
  }
  .difficulty {
    color: #ff6b6b;
    font-size: 12px;
    font-weight: bold;
  }
  .level {
    color: #ffd93d;
    font-size: 12px;
    font-weight: bold;
  }
  .requester {
    color: rgba(255, 255, 255, 0.4);
    font-size: 11px;
  }
</style>
</head>
<body>
  <div class="card">
    <div class="cover"></div>
    <div class="info">
      <div class="song-name">{{SONG_NAME}}</div>
      <div class="difficulty">{{DIFFICULTY}}</div>
      <div class="level">Lv. {{LEVEL}}</div>
      <div class="requester">点歌: {{REQUESTER}}</div>
    </div>
  </div>
</body>
</html>
"""

    static func render(data: SongCardData, template: String = defaultHTML) -> String {
        return template
            .replacingOccurrences(of: "{{SONG_NAME}}", with: data.songName)
            .replacingOccurrences(of: "{{ARTIST}}", with: data.artist)
            .replacingOccurrences(of: "{{DIFFICULTY}}", with: data.difficulty ?? "")
            .replacingOccurrences(of: "{{LEVEL}}", with: data.level ?? "")
            .replacingOccurrences(of: "{{REQUESTER}}", with: data.requester ?? "")
            .replacingOccurrences(of: "{{COVER_URL}}", with: data.coverURL ?? "")
    }
}
