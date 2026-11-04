# EMBER × TEMPEST. Evaluated inside Pipeline; see the skill's references/tasks.md.
{
  # Character and location sheets: text-to-image, no reference photos.
  "char-kaen-v1" => { steps: [Steps::RefBase] },
  "char-arashi-v1" => { steps: [Steps::RefBase] },
  "loc-sky-arena-v1" => { steps: [Steps::RefBase] },
  # One 12 s scene = 288 frames, so the score runs unbroken across all three sections:
  # title 48 frames, layered composite 120, full H3 120.
  # After gen:music this take faded out at 10 s, so the sample holds its climax chord with tools/python/score_tool.py and
  # adds music_from: "output/shonen-s01/03_score_end.wav" here (see the README's editing section).
  "shonen-s01" => {
    steps: [Steps::Dialogue, Steps::Music, Steps::Mix, Steps::Keyframes, Steps::Shots, Steps::Clips, Steps::Overlay],
    **scene(288), music_fade: 0.4, mix: { voice_lift_db: 6, music_db: -5, dialogue_db: 0, duck: true }
  }
}
