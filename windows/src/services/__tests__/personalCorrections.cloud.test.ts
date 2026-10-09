import {expect,it,vi} from "vitest";
const state = vi.hoisted(() => ({entries:[{id:"brand",canonical:"Yinga",variants:["Jengo"],scope:"meeting",enabled:true}]}));
const update = vi.hoisted(() => vi.fn());
vi.mock("../api",()=>({api:{updateNotuleHTML:update}}));
vi.mock("../../stores/personalCorrectionsStore",()=>({usePersonalCorrectionsStore:{getState:()=>({...state,hydrate:async()=>{}})}}));
import {buildObsidianNote} from "../obsidian";
import {persistNotesSection} from "../uploadAndTrack";
it("persists scoped cloud corrections and surfaces failures instead of pretending they were saved",async()=>{
  update.mockResolvedValue(undefined);
  expect(await persistNotesSection("task","<p>Jengo</p>","other")).toBe("<p>Jengo</p>");
  expect(update).not.toHaveBeenCalled();
  expect(await persistNotesSection("task","<p>Jengo</p>","meeting")).toBe("<p>Yinga</p>");
  expect(update).toHaveBeenCalledWith("task","<p>Yinga</p>");
  const note={id:"task",title:"Overleg",raw_transcription:"Jengo",notule_html:update.mock.calls[0][1],duration_seconds:0,tags:[],created_at:"2026-10-09T09:00:00Z",updated_at:"2026-10-09T09:00:00Z"};
  expect(buildObsidianNote(note).markdown).toContain("Yinga");
  expect(note.raw_transcription).toBe("Jengo");
  update.mockRejectedValue(new Error("Opslaan mislukt"));
  await expect(persistNotesSection("task","<p>Jengo</p>","meeting")).rejects.toThrow("Opslaan mislukt");
});
