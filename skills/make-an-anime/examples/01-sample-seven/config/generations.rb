# Sample Seven. No green screen: every shot is one painted H3 take. Evaluated inside Pipeline; see references/tasks.md.
# More: 02-final-inspection (silent score until a beat, hand-built frames), 03-riverbank-bout (paper-cut panels, a
# fight in short cuts), 04-too-salty (73 s, a voice test, reused takes, held stills).
{
  # Sheets first: text-to-image, one run per character and recurring location. A rejected sheet becomes -v2.
  "char-mei-v1" => { steps: [Steps::RefBase] },
  "char-ono-v1" => { steps: [Steps::RefBase] },
  "loc-lab-v1" => { steps: [Steps::RefBase] },
  # One scene of 336 frames (14 s). Voices come before shots because line timings set the shot lengths.
  "lab-s01" => {
    steps: [Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes, Steps::Shots, Steps::Overlay],
    **scene(336), music_fade: 1.0, mix: { voice_lift_db: 6, music_db: -8, dialogue_db: 0, duck: true }
  }
}
