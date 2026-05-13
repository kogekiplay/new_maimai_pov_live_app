import Foundation

struct YOLOPreprocessUniforms {
    var padV: Float
    var padH: Float
    var scale: Float
    var padLeft: Float
    var padTop: Float
    var padRight: Float
    var padBottom: Float
    var stabWidth: Float
    var stabHeight: Float

    init(padding: Int) {
        let yoloIn = Float(Config.yoloInputSize)
        let sw = Float(Config.stabWidth)
        let sh = Float(Config.stabHeight)

        let pv = Float(padding)
        let squareSize = sh + pv * 2
        let ph = (squareSize - sw) / 2.0

        self.padV = pv
        self.padH = ph

        let paddedW = sw + ph * 2
        let paddedH = sh + pv * 2

        scale = yoloIn / max(paddedW, paddedH)

        let newW = Int(paddedW * scale)
        let newH = Int(paddedH * scale)

        let pl = (Config.yoloInputSize - newW) / 2
        let pt = (Config.yoloInputSize - newH) / 2
        let pr = Config.yoloInputSize - newW - pl
        let pb = Config.yoloInputSize - newH - pt

        padLeft = Float(pl)
        padTop = Float(pt)
        padRight = Float(pr)
        padBottom = Float(pb)
        stabWidth = sw
        stabHeight = sh
    }
}
