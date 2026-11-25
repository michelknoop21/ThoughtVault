import { expect, it } from "vitest";
import { CLOUD_STT_PRESETS, cloudSttChoices, cloudSttKeeps } from "../../types";

it("shows the OpenRouter key's transcription models, presets it contains first", () => {
  const listed = ["mistralai/voxtral-small-transcribe-3-0", "openai/gpt-4o-transcribe", "deepgram/nova-3"];
  expect(cloudSttChoices("openrouter", listed)).toEqual(["openai/gpt-4o-transcribe", "deepgram/nova-3", "mistralai/voxtral-small-transcribe-3-0"]);
  expect(cloudSttChoices("openrouter", [])).toEqual(CLOUD_STT_PRESETS.openrouter.models);
  expect(cloudSttChoices("groq", listed)).toEqual(CLOUD_STT_PRESETS.groq.models);
});

it("keeps a routed id until the key's list is known", () => {
  expect(cloudSttKeeps("openrouter", "mistralai/voxtral-small-transcribe-3-0")).toBe(true);
  expect(cloudSttKeeps("openrouter", "gpt-4o-transcribe")).toBe(false);
  expect(cloudSttKeeps("openai", "openai/gpt-4o-transcribe")).toBe(false);
  expect(cloudSttKeeps("custom", "whatever")).toBe(true);
});
