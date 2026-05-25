import Foundation

struct CanvasUniforms {
    var cropX1: Float = 0
    var cropY1: Float = 0
    var cropW: Float = 0
    var cropH: Float = 0
    var stabWidth: Float = Float(Config.stabWidth)
    var stabHeight: Float = Float(Config.stabHeight)
    var canvasWidth: Float = Float(Config.outputWidth)
    var canvasHeight: Float = Float(Config.outputHeight)
    var gameX: Float = Float(Config.gameAreaX)
    var gameY: Float = Float(Config.gameAreaY)
    var gameW: Float = Float(Config.gameAreaWidth)
    var gameH: Float = Float(Config.gameAreaHeight)
    var bgColorR: Float = 0.06
    var bgColorG: Float = 0.06
    var bgColorB: Float = 0.12
}
