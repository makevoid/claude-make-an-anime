module Pipeline
  # Rules that keep footage from reading as pasted-together or AI-generated (references/believable-motion.md).
  #
  # Green screen cannot carry action: a keyed figure has no contact with the ground, no shared light and no shared camera,
  # so a run or a blow looks ridiculous however well it is keyed. The same failure happens without any key, when H3
  # animates a runner's limbs over a background that hardly moves. So action is painted with its world in one H3 take,
  # one runner per shot, with a camera that travels.
  #
  # The written rules run on the prompts, and Shots and Clips refuse them before any paid call. The measured rule runs on
  # the finished take. A word match can be wrong, as in "runs a hand through his hair": such an item states why it is
  # fine in `believable: <reason>`, which the review prints.
  module Believability
    RUN_WORDS = /\b(run(s|ning)?|sprint(s|ing)?|jog(s|ging)?|dash(es|ing)?|charg(e|es|ing)|chas(e|es|ing)|rac(e|es|ing)|flee(s|ing)?|rush(es|ing)?)\b/i
    HIT_WORDS = /\b(punch(es|ing)?|kick(s|ing)?|strik(e|es|ing)|hit(s|ting)?|lung(e|es|ing)|dodg(e|es|ing)|duck(s|ing)?|parr(y|ies|ying)|tackl(e|es|ing)|throw(s|ing)?|swing(s|ing)?|fight(s|ing)?|attack(s|ing)?|clash(es|ing)?|grappl(e|es|ing)|jump(s|ing)?|leap(s|ing)?|fl(y|ies|ying)|fall(s|ing)?)\b/i
    GROUP_WORDS = /\b(each other|both|together|two (men|women|people|fighters|runners|characters|boys|girls)|they)\b/i
    TRACKING_CAMERA = /\b(track(s|ing)?|truck(s|ing)?|follow(s|ing)?|travel(s|ling|ing)?|alongside|steadicam|dolly (beside|with|ahead))\b/i
    NEGATED = /\b(no|not|never|without|nobody|nothing|don't|doesn't)\b[^.,;:]*/i
    PASTED_EFFECTS = /Anim\.(aura|shockRing|impactBloom|speedLines|embers)\b/
    FULL_TURN = /\b(360|full (rotation|orbit|circle|turn)|spin(s|ning)? around)\b/i

    # Near-ground speed below this, in frame widths per second, is a treadmill. Set between two real H3 takes: the two-man
    # run the user rejected as green screen measured 0.11, the tracked single runner that replaced it 0.28. Static shots
    # measure 0.00-0.04. Two runs are a small sample, so read the strip as well.
    MIN_RUN_WORLD_SPEED = 0.20
    MAX_RGB_SPLIT = 0.05

    module_function

    # What the prompt actually asks for: the style bible and the negated phrases are removed, so a style that mentions a
    # fight, or "no running" and "nobody falls", do not count as action.
    def asserted(text)
      text.to_s.sub(Project.style.to_s, " ").gsub(NEGATED, " ")
          .gsub(/\b(?:water|liquid|stream|tap|faucet)\s+(?:is\s+)?running\b|\brunning\s+(?:water|liquid|stream|tap|faucet)\b/i, " ")
    end

    def camera_text(spec)
      camera = spec["camera"]
      camera.is_a?(Hash) ? camera.values.join(" ") : camera.to_s
    end

    def keyed?(spec) = %w[green paper].include?(spec.fetch("key", "paper"))

    def generated?(spec) = !(spec["still"] || spec["color"] || spec["from_run"] || spec["from_take"] || spec["same_take"] || spec["source"])

    def running?(spec) = generated?(spec) && !spec["believable"] && asserted(spec["prompt"]).match?(RUN_WORDS)

    # Problems in one Shots item. Each message says what to do instead.
    def shot_problems(name, spec)
      return [] unless running?(spec)
      problems = []
      unless asserted(camera_text(spec)).match?(TRACKING_CAMERA)
        problems << "#{name}: a run with a camera that does not travel becomes a treadmill. Direct a tracking shot beside or ahead of the runner, with the world passing behind them"
      end
      if run_sentences(spec["prompt"]).any? { _1.match?(GROUP_WORDS) }
        problems << "#{name}: several people run in one shot. Show one runner per shot and let the cut bring them together"
      end
      problems
    end

    # Problems in one Clips item.
    def clip_problems(name, spec)
      return [] if !keyed?(spec) || spec["believable"] || !spec["prompt"]
      text = asserted(spec["prompt"])
      words = [RUN_WORDS, HIT_WORDS].filter_map { text[_1] }
      return [] if words.empty?
      ["#{name}: action (#{words.join(", ")}) on green screen looks ridiculous. Paint the character and the world in one H3 shot instead"]
    end

    def run_sentences(prompt)
      asserted(prompt).split(/(?<=[.!?])\s+/).select { _1.match?(RUN_WORDS) }
    end

    # Softer signals that need a look, not a refusal.
    def warnings(shots:, clips:, overlay: nil)
      out = []
      keyed = clips.select { |_, spec| keyed?(spec) }.keys
      out << "keyed sprites (#{keyed.join(", ")}): check that each stays still and that no sprite travels across the frame in p5" if keyed.any?
      shots.each do |name, spec|
        out << "#{name}: a full camera turn reads as a stunt. Keep the arc partial" if asserted(camera_text(spec)).match?(FULL_TURN)
        out << "#{name}: a p5 roll on the plate needs every layer to turn with it" if spec["roll"]
      end
      effects = overlay.to_s.scan(PASTED_EFFECTS).flatten.uniq
      out << "overlay draws #{effects.join(", ")}: glows and rings sit on top of the painting, so check they do not look pasted on" if effects.any?
      out
    end

    # A colour split is a small fraction of the frame. An amt of 6 instead of 0.006 turned a knockout into four rainbow frames.
    def cue_problems(cues)
      Array(cues).select { |cue| cue["fx"] == "rgb" && cue["amt"].to_f > MAX_RGB_SPLIT }
                 .map { |cue| "vfx rgb at frame #{cue["f"]}: amt #{cue["amt"]} garbles the picture (typical 0.006, at most #{MAX_RGB_SPLIT})" }
    end

    def refuse!(problems)
      raise ArgumentError, "Unbelievable footage refused before any paid call:\n  #{problems.join("\n  ")}\nSee references/believable-motion.md" if problems.any?
    end
  end
end
