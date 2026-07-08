export class PromptBuilder {
  build({ frames, videoMeta, audience, goal }) {
    return {
      system: [
        "You generate step-by-step smartphone operation lessons for elderly users.",
        "Return strict JSON matching the shared lesson schema.",
        "Use relative coordinates from 0 to 1 for every action target."
      ].join(" "),
      user: {
        goal,
        audience,
        videoMeta,
        frameCount: frames.length,
        frameFormat: "base64 data URLs"
      }
    };
  }
}
