export const guideLabels: Record<string, [string, string, string]> = {
  press: [
    "Lower with control",
    "Press above chest",
    "Upper arms gently meet the floor. Exhale as you press; feet stay planted.",
  ],
  row: [
    "Reach down",
    "Pull toward your hip",
    "Keep your torso still. Exhale as you pull. Repeat on both sides.",
  ],
  squat: [
    "Stand tall",
    "Sit between your hips",
    "Keep heels down and the weight close. Inhale down; exhale as you stand.",
  ],
  rdl: [
    "Stand with soft knees",
    "Send your hips back",
    "Weights stay close to your legs. Stop at your comfortable hamstring stretch; exhale to stand.",
  ],
  curl: [
    "Arms by your sides",
    "Bend at the elbows",
    "Elbows stay near your ribs. Exhale as you curl; lower slowly.",
  ],
  kickback: [
    "Bend the elbow",
    "Extend the elbow back",
    "Upper arm stays still. Exhale as you straighten; repeat both sides with a light load.",
  ],
  heel: [
    "Both knees bent",
    "Slide one heel away",
    "Core-control variation. Keep a comfortable neutral back and breathe normally. Return, then switch sides.",
  ],
};
export const guideReferences: Record<
  string,
  { url: string; label: string; camera: string }
> = {
  press: {
    url: "https://www.youtube.com/watch?v=T0Y3OBF1bNI",
    label: "Watch PureGym’s demonstration",
    camera: "Elevated side view · both dumbbells move together",
  },
  row: {
    url: "https://naftaacademy.com/wp-content/uploads/2024/08/NAFTA_Aqua_Aerobic_Manual_2020_Condensed.pdf#page=73",
    label: "Thigh-supported row technique guide · p73",
    camera: "Three-quarter view · free hand supported on thigh",
  },
  squat: {
    url: "https://www.nasm.org/resource-center/exercise-library/goblet-squat",
    label: "Watch NASM’s goblet squat guide",
    camera: "Front view · watch the knees and grounded feet",
  },
  rdl: {
    url: "https://www.nasm.org/resource-center/exercise-library/dumbbell-romanian-deadlift",
    label: "Watch NASM’s Romanian deadlift guide",
    camera: "Side view · hips travel back, weights stay close",
  },
  curl: {
    url: "https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/biceps-curl/vid-20084675",
    label: "Watch Mayo Clinic’s curl demonstration",
    camera: "Three-quarter side view · elbows stay beside the torso",
  },
  kickback: {
    url: "https://www.acefitness.org/resources/everyone/exercise-library/55/triceps-kickback/",
    label: "ACE’s thigh-supported kickback guide",
    camera: "Three-quarter view · upper arm stays still",
  },
  heel: {
    url: "https://www.nhsfife.org/services/all-services/patient-advice/stage-two-exercises-for-your-tummy-muscles/",
    label: "Watch NHS Fife’s core heel slide guide",
    camera: "Side view · the moving heel stays on the mat",
  },
};
