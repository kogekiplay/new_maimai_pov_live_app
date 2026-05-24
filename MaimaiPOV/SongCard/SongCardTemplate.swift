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
    width: 400px;
    height: 120px;
    overflow: hidden;
  }
  .card {
    background: rgba(0, 0, 0, 0.7);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    align-items: center;
    gap: 16px;
    border: 1px solid rgba(255, 255, 255, 0.15);
    width: 400px;
    height: 120px;
  }
  .cover {
    width: 80px;
    height: 80px;
    border-radius: 12px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    flex-shrink: 0;
  }
  .info { flex: 1; overflow: hidden; }
  .song-name {
    color: white;
    font-size: 18px;
    font-weight: bold;
    margin-bottom: 4px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .artist {
    color: rgba(255, 255, 255, 0.6);
    font-size: 14px;
    margin-bottom: 6px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .requester {
    color: rgba(255, 255, 255, 0.4);
    font-size: 12px;
  }
</style>
</head>
<body>
  <div class="card">
    <div class="cover"></div>
    <div class="info">
      <div class="song-name">{{SONG_NAME}}</div>
      <div class="artist">{{ARTIST}}</div>
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
            .replacingOccurrences(of: "{{REQUESTER}}", with: data.requester ?? "")
            .replacingOccurrences(of: "{{COVER_URL}}", with: data.coverURL ?? "")
    }
}
