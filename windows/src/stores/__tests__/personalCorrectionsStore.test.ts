import { expect, it, vi } from "vitest";
const disk = vi.hoisted(()=> ({ document:null as unknown, fail:false }));
vi.mock("@tauri-apps/api/core", () => ({ invoke:vi.fn(async (command:string,args?:{document:unknown}) => {
  if(command === "load_personal_corrections")return disk.document;
  if(disk.fail)throw Error("disk full"); disk.document=JSON.parse(JSON.stringify(args!.document));
}) }));
it("hydrates after restart and failed saves retain last persisted state", async()=> {
  const rule = {id:"yinga",canonical:"Yinga",variants:["Django"],scope:null,enabled:true};
  const {usePersonalCorrectionsStore:store} = await import("../personalCorrectionsStore");
  await store.getState().save(rule);
  expect(store.getState().entries).toEqual([rule]);
  disk.fail=true;
  await expect(store.getState().remove("yinga")).rejects.toThrow("disk full");
  expect(store.getState().entries).toEqual([rule]);
  vi.resetModules();
  const {usePersonalCorrectionsStore: restarted} = await import("../personalCorrectionsStore");
  await restarted.getState().hydrate(); expect(restarted.getState().entries).toEqual([rule]);
});
