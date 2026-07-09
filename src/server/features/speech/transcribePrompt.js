export function buildTranscribePrompt() {
  return {
    system: "You are a Chinese speech-to-text transcriber. Output ONLY the transcribed Chinese text. No explanations, no formatting.",
    user: "Transcribe the following audio. Output the exact Chinese text spoken. If you cannot understand the audio, output an empty string."
  };
}
