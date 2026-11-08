# Too Salty. No green screen: every shot is one painted H3 take. Evaluated inside Pipeline.
{
  "char-hana-v1" => { steps: [Steps::RefBase] },
  "char-kiku-v1" => { steps: [Steps::RefBase] },
  "loc-shop-v1" => { steps: [Steps::RefBase] },
  "loc-street-v1" => { steps: [Steps::RefBase] },
  # Three candidate voices on Kiku's two hardest lines, heard before any scene line is generated.
  "voice-test" => { steps: [Steps::Dialogue], **scene(648) },
  # music_gaps silences the score from the salt line to the cut omelette; music_end/music_out end it before the title.
  "salty-s01" => {
    steps: [Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes, Steps::Shots, Steps::Overlay],
    **scene(1764), music_fade: 1.5,
    mix: { voice_lift_db: 6, music_db: -9, dialogue_db: 0, duck: true, music_gaps: [[22.0, 51.0]], music_end: 71.2, music_out: 1.5 }
  }
}
