# One Round at the River. No green screen: the opening is two painted H3 panels (Clips with key: none) and the fight is
# painted H3. Evaluated inside Pipeline.
{
  # v1 painted both men tan and greyed the gi; v2 is the fix, and cast.yml points at it. Rejected versions stay listed.
  "char-ren-v1" => { steps: [Steps::RefBase] },
  "char-riku-v1" => { steps: [Steps::RefBase] },
  "char-ren-v2" => { steps: [Steps::RefBase] },
  "char-riku-v2" => { steps: [Steps::RefBase] },
  "loc-river-v1" => { steps: [Steps::RefBase] },
  "bout-s01" => {
    steps: [Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes, Steps::Shots, Steps::Clips, Steps::Overlay],
    **scene(410), music_fade: 0.6, mix: { voice_lift_db: 6, music_db: -6, dialogue_db: 0, duck: true }
  }
}
