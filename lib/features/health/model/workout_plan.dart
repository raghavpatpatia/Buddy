import '../../../core/health.dart';
import '../../../core/store.dart';

/// A bodyweight exercise. [seconds] > 0 = timed, else [reps].
class Exercise {
  final String name, emoji, how;
  final int seconds, reps;
  final String? easier; // low-impact substitute name (used when BMI ≥ 25)
  const Exercise(this.name, this.emoji, this.how, {this.seconds = 0, this.reps = 0, this.easier});
  bool get timed => seconds > 0;
}

const _e = {
  // Strength
  'squat': Exercise('Squats', '🦵', 'Feet shoulder-width, sit back like into a chair, chest up, knees over toes.', reps: 15, easier: 'Chair squats'),
  'pushup': Exercise('Push-ups', '💪', 'Straight line head to heels, lower chest to a fist above the floor.', reps: 10, easier: 'Knee push-ups'),
  'bridge': Exercise('Glute bridges', '🍑', 'On your back, knees bent, squeeze glutes and lift hips, pause at top.', reps: 15),
  'lunge': Exercise('Reverse lunges', '🚶', 'Step back, both knees to 90°, push through front heel. Alternate legs.', reps: 12, easier: 'Split squats (hold a wall)'),
  'plank': Exercise('Plank', '🧱', 'Forearms down, body straight, brace your core, breathe.', seconds: 30, easier: 'Knee plank'),
  'superman': Exercise('Supermans', '🦸', 'Face down, lift arms and legs together, hold 2 s, lower.', reps: 12),
  'wallsit': Exercise('Wall sit', '🧍', 'Back flat on a wall, thighs parallel to the floor.', seconds: 30),
  'dips': Exercise('Chair dips', '🪑', 'Hands on a sturdy chair edge, lower until elbows reach 90°.', reps: 10),
  'calf': Exercise('Calf raises', '🦶', 'Rise onto your toes, pause, lower slowly.', reps: 20),
  'deadbug': Exercise('Dead bugs', '🐞', 'On your back, lower opposite arm and leg slowly, keep lower back down.', reps: 12),
  // Cardio
  'jacks': Exercise('Jumping jacks', '⭐', 'Jump feet out while raising arms, then back.', seconds: 40, easier: 'Step jacks'),
  'knees': Exercise('High knees', '🏃', 'Run on the spot driving knees up to hip height.', seconds: 30, easier: 'Marching in place'),
  'climbers': Exercise('Mountain climbers', '⛰️', 'Plank position, drive knees to chest one at a time.', seconds: 30, easier: 'Slow climbers'),
  'burpee': Exercise('Burpees', '💥', 'Squat, kick back to plank, return, jump up.', reps: 8, easier: 'Step-back burpees (no jump)'),
  'skater': Exercise('Skaters', '⛸️', 'Leap side to side landing on one foot.', seconds: 30, easier: 'Side steps'),
  // Mobility / desk-worker
  'neck': Exercise('Neck & shoulder rolls', '🙆', 'Slow circles each way. Release that coding hunch.', seconds: 40),
  'wrist': Exercise('Wrist stretches', '🤲', 'Arm straight, gently pull fingers back, then down. Both hands.', seconds: 40),
  'catcow': Exercise('Cat–cow', '🐈', 'On hands and knees, round then arch your back with your breath.', seconds: 40),
  'dog': Exercise('Downward dog', '🐕', 'Hips high, heels toward the floor, long spine.', seconds: 30),
  'cobra': Exercise('Cobra', '🐍', 'Face down, press chest up gently, hips stay down.', seconds: 30),
  'hipflex': Exercise('Hip-flexor stretch', '🧘', 'Half-kneel, tuck pelvis, lean forward. Undo hours of sitting.', seconds: 40),
  'hamstring': Exercise('Hamstring stretch', '🦿', 'Leg straight on a low surface, hinge at the hips.', seconds: 40),
  'child': Exercise('Child’s pose', '🙇', 'Kneel, sit back on heels, arms long, breathe slowly.', seconds: 45),
  // Dance
  'groove': Exercise('Warm-up groove', '🎶', 'Easy steps, shoulder rolls, bounce to the beat.', seconds: 120),
  'freestyle': Exercise('Freestyle dance', '💃', 'Put on a favourite song and move non-stop. Big arms, bend the knees!', seconds: 240),
  'bolly': Exercise('Bollywood cardio', '🕺', 'Upbeat Bollywood track: bhangra shoulders, side steps, jumps.', seconds: 240),
  'hiphop': Exercise('Hip-hop basics', '🎧', 'Bounce, step-touch, body rolls, arm waves. Practise isolations.', seconds: 180),
  'cooldown': Exercise('Cool-down sway', '🌙', 'Slow song, gentle sways and stretches, deep breaths.', seconds: 120),
  // Walk
  'walk': Exercise('Brisk walk', '🚶‍♂️', 'Walk fast enough that talking is a little hard. Outside is best.', seconds: 1200),
};

class Workout {
  final String id, title, emoji, logType, why;
  final List<String> items;
  final int rounds, restSec;
  const Workout(this.id, this.title, this.emoji, this.logType, this.why, this.items, {this.rounds = 2, this.restSec = 20});

  /// Steps with low-impact substitutions when [easy].
  List<Exercise> steps({bool easy = false}) => [
        for (var r = 0; r < rounds; r++)
          for (final id in items)
            (() {
              final e = _e[id]!;
              return easy && e.easier != null ? Exercise(e.easier!, e.emoji, e.how, seconds: e.seconds, reps: e.reps) : e;
            })(),
      ];

  int estMinutes({bool easy = false}) {
    final s = steps(easy: easy);
    final secs = s.fold<int>(0, (a, e) => a + (e.timed ? e.seconds : e.reps * 3)) + restSec * (s.length - 1);
    return (secs / 60).ceil();
  }
}

const workouts = <String, Workout>{
  'full': Workout('full', 'Full-body strength', '🏋️', 'Gym', 'Builds muscle, which raises your metabolism.', ['squat', 'pushup', 'bridge', 'plank', 'superman']),
  'lower': Workout('lower', 'Legs & core', '🦵', 'Gym', 'Biggest muscles burn the most energy.', ['squat', 'lunge', 'wallsit', 'calf', 'deadbug']),
  'upper': Workout('upper', 'Upper body & core', '💪', 'Gym', 'Posture and strength for long desk days.', ['pushup', 'dips', 'superman', 'plank', 'deadbug']),
  'hiit': Workout('hiit', 'HIIT burner', '🔥', 'HIIT', 'Short and intense: the best fat-burn per minute.', ['jacks', 'climbers', 'burpee', 'knees', 'skater'], rounds: 3, restSec: 15),
  'dance': Workout('dance', 'Dance cardio', '💃', 'Dance', 'Cardio that doesn’t feel like cardio. Burns ~6 kcal/min.', ['groove', 'bolly', 'freestyle', 'hiphop', 'cooldown'], rounds: 1, restSec: 10),
  'mobility': Workout('mobility', 'Desk-worker mobility', '🧘', 'Yoga', 'Undo hours of sitting: neck, wrists, hips, back.', ['neck', 'wrist', 'catcow', 'dog', 'cobra', 'hipflex', 'hamstring', 'child'], rounds: 1, restSec: 5),
  'walk': Workout('walk', 'Brisk walk + stretch', '🚶', 'Walk', 'Active recovery: easy on joints, great for the mind.', ['walk', 'hamstring', 'hipflex'], rounds: 1, restSec: 10),
};

/// Today's plan from the weekday, adjusted for your goal.
Workout todaysWorkout([DateTime? d]) {
  final goal = Store.profile['goal'] as String? ?? 'maintain';
  final wd = (d ?? DateTime.now()).weekday;
  // Mon..Sun
  final week = switch (goal) {
    'lose' => ['full', 'dance', 'lower', 'mobility', 'hiit', 'dance', 'walk'],
    'gain' => ['full', 'mobility', 'lower', 'dance', 'upper', 'full', 'walk'],
    _ => ['full', 'dance', 'lower', 'mobility', 'upper', 'dance', 'walk'],
  };
  final w = workouts[week[wd - 1]]!;
  // Building muscle: one extra round of strength work.
  if (goal == 'gain' && w.logType == 'Gym') {
    return Workout(w.id, w.title, w.emoji, w.logType, w.why, w.items, rounds: 3, restSec: 30);
  }
  return w;
}

/// Low-impact versions when BMI is in the overweight/obese range (protects knees).
bool get useEasyVersions {
  final b = Body.fromProfile();
  return b != null && b.bmi >= 25;
}
