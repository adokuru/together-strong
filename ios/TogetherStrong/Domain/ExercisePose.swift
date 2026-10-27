import Foundation

struct PosePoint: Equatable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    func shifted(_ x: Double, _ y: Double) -> PosePoint { PosePoint(self.x + x, self.y + y) }
}

struct ExercisePose {
    var head: PosePoint
    var body: [PosePoint]
    var arms: [[PosePoint]]
    var legs: [[PosePoint]]
    var weights: [PosePoint]

    private static func point(_ origin: PosePoint, _ length: Double, _ degrees: Double) -> PosePoint {
        PosePoint(origin.x + length * cos(degrees * .pi / 180), origin.y + length * sin(degrees * .pi / 180))
    }
    private static func knee(_ hip: PosePoint, _ ankle: PosePoint, _ upper: Double, _ lower: Double, _ side: Double) -> PosePoint {
        let dx = ankle.x - hip.x, dy = ankle.y - hip.y, distance = hypot(dx, dy)
        let along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
        let height = sqrt(max(0, upper * upper - along * along))
        return PosePoint(hip.x + dx / distance * along - dy / distance * height * side,
                         hip.y + dy / distance * along + dx / distance * height * side)
    }
    static func make(_ id: String, progress: Double) -> ExercisePose {
        let t = min(1, max(0, progress))
        switch id {
        case "press":
            let shoulder = PosePoint(45, 118), elbow = point(shoulder, 26, -88 * t), wrist = point(elbow, 26, -90)
            return ExercisePose(head: PosePoint(27,113), body: [PosePoint(38,118),PosePoint(86,118)],
                arms: [[shoulder,elbow,wrist]], legs: [[PosePoint(86,118),PosePoint(105,94),PosePoint(125,122)]], weights: [wrist.shifted(0,-4)])
        case "row", "kickback":
            let shoulder = PosePoint(58,50)
            let elbow = point(shoulder,27,id == "row" ? 90 - 65*t : 30)
            let wrist = point(elbow,26,id == "row" ? 90 - 20*t : 90 - 60*t)
            return ExercisePose(head: PosePoint(45,40), body: [PosePoint(54,49),PosePoint(104,78)],
                arms: [[shoulder,elbow,wrist],[PosePoint(61,52),PosePoint(76,78),PosePoint(87,87)]],
                legs: [[PosePoint(104,78),PosePoint(76,96),PosePoint(67,122)],[PosePoint(104,78),PosePoint(117,98),PosePoint(130,122)]], weights: [wrist.shifted(0,4)])
        case "squat":
            let hip = PosePoint(80,69+26*t), shoulder = hip.shifted(0,-40), left = PosePoint(54,122), right = PosePoint(106,122)
            return ExercisePose(head: shoulder.shifted(0,-13), body: [shoulder,hip],
                arms: [[shoulder.shifted(-11,5),shoulder.shifted(-16,22),shoulder.shifted(-1,10)], [shoulder.shifted(11,5),shoulder.shifted(16,22),shoulder.shifted(1,10)]],
                legs: [[hip.shifted(-6,0),knee(hip.shifted(-6,0),left,29,29,1),left],[hip.shifted(6,0),knee(hip.shifted(6,0),right,29,29,-1),right]], weights: [shoulder.shifted(0,10)])
        case "rdl":
            let hip = PosePoint(95+14*t,71+2*t), shoulder = point(hip,34,-90-50*t), head = point(shoulder,13,-90-50*t)
            let near = shoulder.shifted(4,3), far = shoulder.shifted(-4,1), ankle = PosePoint(100,122), other = PosePoint(112,122), otherHip = hip.shifted(7,0)
            return ExercisePose(head: head, body: [shoulder,hip],
                arms: [[near,near.shifted(0,24),near.shifted(0,46)],[far,far.shifted(0,24),far.shifted(0,46)]],
                legs: [[hip,knee(hip,ankle,27,25,1),ankle],[otherHip,knee(otherHip,other,27,25,1),other]], weights: [near.shifted(0,50),far.shifted(0,50)])
        case "curl":
            let near = PosePoint(79,65), far = PosePoint(87,62), nearWrist = point(near,25,90+150*t), farWrist = point(far,25,90+150*t)
            return ExercisePose(head: PosePoint(80,23), body: [PosePoint(80,36),PosePoint(84,78)],
                arms: [[PosePoint(79,41),near,nearWrist],[PosePoint(87,38),far,farWrist]],
                legs: [[PosePoint(82,78),PosePoint(80,100),PosePoint(81,122)],[PosePoint(89,78),PosePoint(93,100),PosePoint(96,122)]], weights: [nearWrist,farWrist])
        default:
            precondition(id == "heel", "ExercisePose requires a known exercise ID")
            let hip = PosePoint(78,118), moving = PosePoint(112+30*t,122), other = PosePoint(118,122)
            return ExercisePose(head: PosePoint(26,113), body: [PosePoint(37,118),hip],
                arms: [[PosePoint(45,118),PosePoint(63,123),PosePoint(79,123)]],
                legs: [[hip,knee(hip,other,34,34,-1),other],[hip,knee(hip,moving,34,34,-1),moving]], weights: [])
        }
    }
}

struct GuidePlayback {
    private(set) var progress = 0.0
    private var phase = 0.0
    private(set) var playing = false
    var speed = 0.5
    mutating func play() { playing = true }
    mutating func pause() { playing = false }
    mutating func scrub(_ position: Double) {
        playing = false; progress = min(1,max(0,position))
        phase = acos(1 - 2 * progress) / (2 * .pi)
    }
    mutating func advance(seconds: Double) {
        guard playing else { return }
        phase = (phase + min(0.1,max(0,seconds)) * speed / 6).truncatingRemainder(dividingBy: 1)
        progress = (1 - cos(phase * 2 * .pi)) / 2
    }
}
