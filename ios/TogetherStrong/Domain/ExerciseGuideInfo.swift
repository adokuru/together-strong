// Generated from lib/exercise-guides.ts by scripts/generate-motion-fixtures.mjs.
import Foundation

struct ExerciseGuideInfo {
    let start: String
    let finish: String
    let cue: String
    let camera: String
    let reference: String
    let referenceLabel: String
    static let all: [String: ExerciseGuideInfo] = [
        "press": ExerciseGuideInfo(start: "Lower with control", finish: "Press above chest", cue: "Upper arms gently meet the floor. Exhale as you press; feet stay planted.", camera: "Elevated side view · both dumbbells move together", reference: "https://www.youtube.com/watch?v=T0Y3OBF1bNI", referenceLabel: "Watch PureGym’s demonstration"),
        "row": ExerciseGuideInfo(start: "Reach down", finish: "Pull toward your hip", cue: "Keep your torso still. Exhale as you pull. Repeat on both sides.", camera: "Three-quarter view · free hand supported on thigh", reference: "https://naftaacademy.com/wp-content/uploads/2024/08/NAFTA_Aqua_Aerobic_Manual_2020_Condensed.pdf#page=73", referenceLabel: "Thigh-supported row technique guide · p73"),
        "squat": ExerciseGuideInfo(start: "Stand tall", finish: "Sit between your hips", cue: "Keep heels down and the weight close. Inhale down; exhale as you stand.", camera: "Front view · watch the knees and grounded feet", reference: "https://www.nasm.org/resource-center/exercise-library/goblet-squat", referenceLabel: "Watch NASM’s goblet squat guide"),
        "rdl": ExerciseGuideInfo(start: "Stand with soft knees", finish: "Send your hips back", cue: "Weights stay close to your legs. Stop at your comfortable hamstring stretch; exhale to stand.", camera: "Side view · hips travel back, weights stay close", reference: "https://www.nasm.org/resource-center/exercise-library/dumbbell-romanian-deadlift", referenceLabel: "Watch NASM’s Romanian deadlift guide"),
        "curl": ExerciseGuideInfo(start: "Arms by your sides", finish: "Bend at the elbows", cue: "Elbows stay near your ribs. Exhale as you curl; lower slowly.", camera: "Three-quarter side view · elbows stay beside the torso", reference: "https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/biceps-curl/vid-20084675", referenceLabel: "Watch Mayo Clinic’s curl demonstration"),
        "kickback": ExerciseGuideInfo(start: "Bend the elbow", finish: "Extend the elbow back", cue: "Upper arm stays still. Exhale as you straighten; repeat both sides with a light load.", camera: "Three-quarter view · upper arm stays still", reference: "https://www.acefitness.org/resources/everyone/exercise-library/55/triceps-kickback/", referenceLabel: "ACE’s thigh-supported kickback guide"),
        "heel": ExerciseGuideInfo(start: "Both knees bent", finish: "Slide one heel away", cue: "Core-control variation. Keep a comfortable neutral back and breathe normally. Return, then switch sides.", camera: "Side view · the moving heel stays on the mat", reference: "https://www.nhsfife.org/services/all-services/patient-advice/stage-two-exercises-for-your-tummy-muscles/", referenceLabel: "Watch NHS Fife’s core heel slide guide")
    ]
}
