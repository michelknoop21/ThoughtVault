import { expect, it } from "vitest";
import { transcriptionAdvice } from "../processingAdvice";
import type { SystemSpecs } from "../tauriCommands";

const pc: SystemSpecs = { cpu: "QA CPU", architecture: "x86_64", memory_gb: 16, threads: 8, os_version: "Windows", free_storage_gb: 5 };
it("offers only CPU models recommended for the measured system", () => {
  expect(transcriptionAdvice(pc)).toMatchObject({ model: "medium", models: ["small", "medium"] });
  expect(transcriptionAdvice({ ...pc, memory_gb: 8 })).toMatchObject({ model: "small", models: ["small"] });
  expect(transcriptionAdvice({ ...pc, free_storage_gb: 0.5 }).models).toEqual(["small", "medium"]);
});
it("warns on limited resources without blocking local inference", () => {
  for (const specs of [{ ...pc, memory_gb: 4 }, { ...pc, threads: 2 }]) {
    expect(transcriptionAdvice(specs)).toMatchObject({ model: "small", models: ["small"] });
    expect(transcriptionAdvice(specs).reason).toContain("lang duren");
  }
});
it("does not invent advice for missing or invalid measurements", () => {
  for (const specs of [null, { ...pc, memory_gb: 0 }, { ...pc, threads: NaN }]) {
    expect(transcriptionAdvice(specs)).toMatchObject({ model: null, models: [] });
  }
});
