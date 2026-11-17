import {beforeEach,expect,it,vi} from "vitest";
import {invoke} from "@tauri-apps/api/core";
import {modelRequest} from "../modelTransport";
import type {RequestTrace} from "../modelRequestLog";
vi.mock("@tauri-apps/api/core",()=>({invoke:vi.fn()}));
vi.mock("../modelRequestLog",()=>({logRetry:vi.fn(),TIME_LIMIT_MESSAGE:"timeout"}));
const request={url:"http://localhost:11434/v1/chat/completions",headers:{},body:"{}"};
const trace=(signal:AbortSignal):RequestTrace=>({provider:"local",model:"fixture",system:"",user:"",signal});
beforeEach(()=>vi.clearAllMocks());
it("never sends a request cancelled during native registration",async()=>{
 const abort=new AbortController();let registered!:(id:string)=>void;
 vi.mocked(invoke).mockImplementation(async command=>command==="register_proxy_request"?new Promise(resolve=>{registered=resolve as typeof registered;}):undefined);
 const pending=modelRequest(request,trace(abort.signal));abort.abort();registered("id");
 await expect(pending).rejects.toMatchObject({name:"AbortError"});
 expect(invoke).not.toHaveBeenCalledWith("proxy_request",expect.anything());
 expect(invoke).toHaveBeenCalledWith("cancel_proxy_request",{requestId:"id"});
});
it("cancels the native request, without retrying it",async()=>{
 const abort=new AbortController();let reject!:(reason:string)=>void;
 vi.mocked(invoke).mockImplementation(async command=>{
  if(command==="register_proxy_request")return "id";
  if(command==="proxy_request")return new Promise((_resolve,r)=>{reject=r;});
  if(command==="cancel_proxy_request")reject("Geannuleerd");
 });
 const pending=modelRequest(request,trace(abort.signal));
 await vi.waitFor(()=>expect(reject).toBeTypeOf("function"));abort.abort();
 await expect(pending).rejects.toMatchObject({name:"AbortError"});
 expect(vi.mocked(invoke).mock.calls.filter(call=>call[0]==="proxy_request")).toHaveLength(1);
});
it("cancels a rate-limit wait before a second request",async()=>{
 const abort=new AbortController();
 vi.mocked(invoke).mockImplementation(async command=>command==="register_proxy_request"?"id":command==="proxy_request"?{status:429,body:"",headers:{"Retry-After":"30"}}:undefined);
 const pending=modelRequest(request,trace(abort.signal));
 await vi.waitFor(()=>expect(invoke).toHaveBeenCalledWith("proxy_request",expect.anything()));abort.abort();
 await expect(pending).rejects.toMatchObject({name:"AbortError"});
 expect(vi.mocked(invoke).mock.calls.filter(call=>call[0]==="proxy_request")).toHaveLength(1);
});
