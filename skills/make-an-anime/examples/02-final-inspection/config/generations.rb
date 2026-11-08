# Final Inspection. No green screen: every shot is one painted H3 take. Evaluated inside Pipeline.
{
  "char-tetsu-v1" => { steps: [Steps::RefBase] },
  "char-robot-v1" => { steps: [Steps::RefBase] },  # a machine gets a character sheet like a person
  "loc-yard-v1" => { steps: [Steps::RefBase] },
  # No Clips step: nobody is keyed. music_gaps keeps the score silent until the amber light (21 s), music_back fades it in.
  "fi-s01" => {
    steps: [Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes, Steps::Shots, Steps::Overlay],
    **scene(816), music_fade: 1.5,
    mix: { voice_lift_db: 6, music_db: -9, dialogue_db: 0, duck: true, music_gaps: [[0.0, 21.0]], music_back: 2.5 }
  }
}
