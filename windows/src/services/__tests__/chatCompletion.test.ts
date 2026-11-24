import { expect, it } from "vitest";
import { readChatCompletion } from "../chatCompletion";

it("refuses a stream that closes before completion", () => {
  const delta = 'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n';
  expect(readChatCompletion(delta).streamError).toBe("onvolledig");
  expect(readChatCompletion(delta + "data: [DONE]\n").streamError).toBeUndefined();
  expect(readChatCompletion(delta + 'data: {"choices":[{"finish_reason":"stop"}]}\n').text).toBe("partial");
});
