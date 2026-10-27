// Generated from lib/workout.ts by scripts/generate-workout-fixtures.mjs.
import Foundation

struct Exercise: Codable, Equatable {
    let id: String
    let name: String
    let group: String
    let reps: String
    let maxReps: Int
    var sets: Int
    let rest: Int
    let instructions: String
    let cue: String
    let side: Bool
    let bodyweight: Bool

    static let all: [Exercise] = [
        Exercise(id: "press", name: "Dumbbell floor press", group: "CHEST · TRICEPS", reps: "8–12", maxReps: 12, sets: 3, rest: 120, instructions: "Lie on the floor with knees bent. Hold dumbbells over your chest, palms forward or slightly inward. Lower slowly until upper arms gently touch the floor, then press up. Keep wrists stacked and avoid bouncing.", cue: "Slow lower. Smooth press.", side: false, bodyweight: false),
        Exercise(id: "row", name: "One-arm dumbbell row", group: "BACK · BICEPS", reps: "8–12", maxReps: 12, sets: 2, rest: 120, instructions: "Hinge forward with a flat, comfortable back and a staggered stance. Rest your free hand on your front thigh. Pull one dumbbell toward your hip without twisting, then lower slowly. Complete both sides; log the lower rep count.", cue: "Pull toward your hip.", side: true, bodyweight: false),
        Exercise(id: "squat", name: "Goblet squat", group: "LEGS · CORE", reps: "8–12", maxReps: 12, sets: 2, rest: 120, instructions: "Hold one dumbbell close to your chest. Stand with feet in a comfortable stance. Sit down between your hips to a comfortable depth, keeping heels grounded and knees tracking with toes. Stand tall without locking your knees.", cue: "Stay tall. Keep heels down.", side: false, bodyweight: false),
        Exercise(id: "rdl", name: "Dumbbell Romanian deadlift", group: "GLUTES · HAMSTRINGS", reps: "8–12", maxReps: 12, sets: 2, rest: 120, instructions: "Stand with soft knees and dumbbells near your thighs. Push your hips back, keeping the weights close and your back comfortable. Stop when you feel a hamstring stretch and can maintain form, then stand by bringing your hips forward.", cue: "Hips back, weights close.", side: false, bodyweight: false),
        Exercise(id: "curl", name: "Dumbbell curls", group: "BICEPS", reps: "10–15", maxReps: 15, sets: 2, rest: 90, instructions: "Stand tall with a dumbbell in each hand. Keep elbows close to your sides. Curl without swinging or leaning, then lower under control. Log the lower rep count if the arms differ.", cue: "Quiet elbows. No swinging.", side: false, bodyweight: false),
        Exercise(id: "kickback", name: "Light triceps kickback", group: "TRICEPS", reps: "10–15", maxReps: 15, sets: 2, rest: 90, instructions: "Use a light dumbbell. Hinge slightly and support your free hand on your thigh. Hold your upper arm close to your body. Straighten the elbow without moving the shoulder, then return slowly. Repeat both sides; log the lower rep count.", cue: "Light load. Upper arm still.", side: true, bodyweight: false),
        Exercise(id: "heel", name: "Bodyweight heel slides", group: "CORE · CONTROL", reps: "6–10", maxReps: 10, sets: 2, rest: 60, instructions: "Lie on your back with knees bent and heels on the floor. Gently brace while breathing normally. Slide one heel away only as far as you can without arching your back, then return. Alternate sides and log reps per side.", cue: "Breathe. Move with control.", side: true, bodyweight: true)
    ]

    static func routine(_ profile: Profile) -> [Exercise] {
        let order = profile == .david ? ["press", "row", "squat", "rdl", "curl", "kickback", "heel"] : ["row", "squat", "press", "rdl", "curl", "kickback", "heel"]
        return order.compactMap { id in
            guard var exercise = all.first(where: { $0.id == id }) else { return nil }
            exercise.sets = (profile == .david && id == "press") || (profile == .mary && id == "row") ? 3 : 2
            return exercise
        }
    }
}
