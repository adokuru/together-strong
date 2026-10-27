import UIKit

@MainActor
final class ExerciseCanvasView: UIView {
    let exerciseID: String
    var position: Double = 0 { didSet { setNeedsDisplay(); accessibilityValue = "\(Int(position * 100)) percent" } }
    private let skin = UIColor(red: 0.88, green: 0.66, blue: 0.51, alpha: 1)
    private let shirt = UIColor(red: 0.15, green: 0.41, blue: 0.45, alpha: 1)
    private let pants = UIColor(red: 0.20, green: 0.30, blue: 0.38, alpha: 1)

    init(exerciseID: String, name: String, accessible: Bool = true) {
        self.exerciseID = exerciseID; super.init(frame: .zero)
        backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.14, alpha: 1) : UIColor(red: 0.94, green: 0.97, blue: 0.97, alpha: 1) }
        layer.cornerRadius = 16; clipsToBounds = true; contentMode = .redraw
        isAccessibilityElement = accessible; accessibilityLabel = "\(name) movement illustration"
        accessibilityValue = "0 percent"; accessibilityTraits = .image
        accessibilityIdentifier = accessible ? "guideCanvas" : nil
    }
    required init?(coder: NSCoder) { fatalError("Use init(exerciseID:name:)") }

    private func path(_ a: PosePoint, _ b: PosePoint, _ widthA: Double, _ widthB: Double) -> UIBezierPath {
        let dx = b.x - a.x, dy = b.y - a.y, length = max(0.001,hypot(dx,dy)), nx = -dy/length, ny = dx/length
        let p = UIBezierPath(); p.move(to: CGPoint(x:a.x+nx*widthA,y:a.y+ny*widthA))
        p.addQuadCurve(to: CGPoint(x:b.x+nx*widthB,y:b.y+ny*widthB), controlPoint: CGPoint(x:a.x+dx*0.48+nx*widthA*1.08,y:a.y+dy*0.48+ny*widthA*1.08))
        p.addQuadCurve(to: CGPoint(x:b.x-nx*widthB,y:b.y-ny*widthB), controlPoint: CGPoint(x:b.x+dx*0.05,y:b.y+dy*0.05))
        p.addQuadCurve(to: CGPoint(x:a.x-nx*widthA,y:a.y-ny*widthA), controlPoint: CGPoint(x:a.x+dx*0.48-nx*widthA*1.08,y:a.y+dy*0.48-ny*widthA*1.08))
        p.close(); return p
    }
    private func fill(_ path: UIBezierPath, _ color: UIColor, shaded: Bool = true) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); path.addClip()
        if shaded, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.withAlphaComponent(0.75).cgColor,color.cgColor,color.withAlphaComponent(0.9).cgColor] as CFArray, locations: [0,0.55,1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x:path.bounds.minX,y:path.bounds.minY), end: CGPoint(x:path.bounds.maxX,y:path.bounds.maxY), options: [])
        } else { color.setFill(); path.fill() }
        context.restoreGState()
        UIColor(red:0.13,green:0.24,blue:0.30,alpha:0.15).setStroke(); path.lineWidth = 0.5; path.stroke()
    }
    private func limb(_ points: [PosePoint], _ widths: [Double], _ color: UIColor) {
        guard points.count == widths.count else { return }
        for i in 1..<points.count { fill(path(points[i-1],points[i],widths[i-1],widths[i]),color) }
        for i in 1..<(points.count-1) { color.setFill(); UIBezierPath(ovalIn:CGRect(x:points[i].x-widths[i],y:points[i].y-widths[i]*0.9,width:widths[i]*2,height:widths[i]*1.8)).fill() }
    }
    private func shoe(_ p: PosePoint, far: Bool = false) {
        fill(UIBezierPath(roundedRect: CGRect(x:p.x-6,y:p.y-3,width:17,height:8),cornerRadius:3),far ? .lightGray : UIColor(red:0.88,green:0.93,blue:0.94,alpha:1),shaded:false)
    }
    private func weight(_ p: PosePoint, far: Bool = false) {
        UIColor.gray.setFill(); UIBezierPath(roundedRect:CGRect(x:p.x-10,y:p.y-2,width:20,height:4),cornerRadius:1).fill()
        let color = far ? UIColor(red:0.45,green:0.53,blue:0.58,alpha:1) : UIColor(red:0.17,green:0.27,blue:0.34,alpha:1)
        for x in [p.x-12,p.x+5] { fill(UIBezierPath(roundedRect:CGRect(x:x,y:p.y-6,width:7,height:12),cornerRadius:1.5),color) }
        skin.setFill(); UIBezierPath(ovalIn:CGRect(x:p.x-3.5,y:p.y-4,width:7,height:6)).fill()
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        let scale = min(bounds.width/155,bounds.height/142)
        context.translateBy(x:(bounds.width-155*scale)/2,y:(bounds.height-142*scale)/2)
        context.scaleBy(x:scale,y:scale); context.translateBy(x:-5,y:-2)
        let pose = ExercisePose.make(exerciseID, progress: position)
        let floor = ["press","heel"].contains(exerciseID), nearLeg = exerciseID == "heel" ? 1 : 0
        UIColor(red:0.77,green:0.85,blue:0.87,alpha:1).setFill()
        if floor { UIBezierPath(roundedRect:CGRect(x:11,y:125,width:145,height:6),cornerRadius:2).fill() }
        else { UIColor.black.withAlphaComponent(0.08).setFill(); UIBezierPath(ovalIn:CGRect(x:33,y:125,width:110,height:6)).fill() }
        for (i,leg) in pose.legs.enumerated() where i != nearLeg {
            limb(leg,[6.5,4.6,3],UIColor(red:0.47,green:0.55,blue:0.61,alpha:1)); if let foot = leg.last { shoe(foot,far:true) }
        }
        if pose.arms.count > 1 { limb(pose.arms[1],[5.5,4,2.4],UIColor(red:0.75,green:0.56,blue:0.46,alpha:1)) }
        if exerciseID == "press" {
            limb(pose.arms[0].map { $0.shifted(5,-3) },[5.5,4,2.4],UIColor(red:0.75,green:0.56,blue:0.46,alpha:1))
            weight(pose.weights[0].shifted(5,-3),far:true)
        }
        limb(pose.legs[nearLeg],[7,5,3.2],pants); if let foot = pose.legs[nearLeg].last { shoe(foot) }
        let shoulder = pose.body[0], hip = pose.body[1], front = exerciseID == "squat"
        fill(path(shoulder,hip,front ? 13 : floor ? 7 : 10,front ? 10 : 8),shirt)
        let waist = PosePoint(shoulder.x+(hip.x-shoulder.x)*0.77,shoulder.y+(hip.y-shoulder.y)*0.77)
        fill(path(waist,hip,front ? 10 : 8,front ? 11 : 8),pants)
        fill(path(pose.head,shoulder,3.2,4.3),skin)
        context.saveGState(); context.translateBy(x:pose.head.x,y:pose.head.y)
        if floor { context.rotate(by:70 * .pi/180) }
        fill(UIBezierPath(ovalIn:CGRect(x:-7.8,y:-9,width:15.6,height:18)),skin)
        UIColor(red:0.2,green:0.26,blue:0.30,alpha:1).setFill()
        let hair = UIBezierPath(); hair.move(to:CGPoint(x:-7.8,y:-1)); hair.addQuadCurve(to:CGPoint(x:7.5,y:1),controlPoint:CGPoint(x:0,y:-20)); hair.addLine(to:CGPoint(x:5,y:-4)); hair.addQuadCurve(to:CGPoint(x:-7.8,y:-1),controlPoint:CGPoint(x:-1,y:-8)); hair.close(); hair.fill()
        UIColor.darkGray.setFill()
        if front { for x in [-3.0,2] { UIBezierPath(ovalIn:CGRect(x:x,y:1,width:1.2,height:1.2)).fill() } }
        else { UIBezierPath(ovalIn:CGRect(x:-5,y:0,width:1.4,height:1.4)).fill() }
        context.restoreGState()
        limb(pose.arms[0],[6,4.2,2.5],skin)
        let arm = pose.arms[0], sleeve = PosePoint(arm[0].x+(arm[1].x-arm[0].x)*0.3,arm[0].y+(arm[1].y-arm[0].y)*0.3)
        fill(path(arm[0],sleeve,6.4,5.8),shirt)
        for (i,p) in pose.weights.enumerated() { weight(p,far:i>0) }
        context.restoreGState()
    }
}
