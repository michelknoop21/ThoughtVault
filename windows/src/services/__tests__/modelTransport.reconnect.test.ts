import {afterEach,beforeEach,expect,it,vi} from "vitest";
import {invoke} from "@tauri-apps/api/core";
import {CONNECTION_RETRY_WAIT_MS,modelRequest} from "../modelTransport";
import {logRetry,type RequestTrace} from "../modelRequestLog";
vi.mock("@tauri-apps/api/core",()=>({invoke:vi.fn()}));
vi.mock("../modelRequestLog",()=>({logRetry:vi.fn(),TIME_LIMIT_MESSAGE:"timeout"}));
// TV-000024: both notule requests to the routed provider lost their connection at once; one retry should carry them.
const remote={url:"https://openrouter.ai/api/v1/chat/completions",headers:{},body:"{}"};
const local={url:"http://localhost:11434/v1/chat/completions",headers:{},body:"{}"};
const trace=(signal?:AbortSignal):RequestTrace=>({provider:"openrouter",model:"fixture",system:"",user:"",signal});
const lost="error sending request for url (https://openrouter.ai/api/v1/chat/completions)";
const ok={status:200,body:"{}"};
const sends=()=>vi.mocked(invoke).mock.calls.filter(call=>call[0]==="proxy_request");
function replies(...answers:unknown[]){
 vi.mocked(invoke).mockImplementation(async command=>{
  if(command!=="proxy_request")return command==="register_proxy_request"?"id":undefined;
  const answer=answers.shift();
  if(typeof answer==="string")throw answer;
  return answer;
 });
}
beforeEach(()=>{vi.clearAllMocks();vi.useFakeTimers();});
afterEach(()=>vi.useRealTimers());
it("sends a remote request once more after its connection broke",async()=>{
 replies(lost,ok);
 const pending=modelRequest(remote,trace(),{total:3600,idle:300});
 await vi.advanceTimersByTimeAsync(CONNECTION_RETRY_WAIT_MS);
 await expect(pending).resolves.toEqual(ok);
 expect(sends()).toHaveLength(2);
 expect(logRetry).toHaveBeenCalledWith(expect.anything(),CONNECTION_RETRY_WAIT_MS,"connection error");
 // The retry gets the remaining time, not a fresh limit.
 expect((sends()[1][1] as {request:{timeout_seconds:number}}).request.timeout_seconds).toBeLessThan(3600);
});
it("reports the connection failure when the retry breaks too",async()=>{
 replies(lost,lost);
 const pending=modelRequest(remote,trace());
 const settled=expect(pending).rejects.toBe(lost);
 await vi.advanceTimersByTimeAsync(CONNECTION_RETRY_WAIT_MS);
 await settled;
 expect(sends()).toHaveLength(2);
});
it("does not retry a local server that refuses the connection",async()=>{
 replies("connection refused",ok);
 await expect(modelRequest(local,trace())).rejects.toBe("connection refused");
 expect(sends()).toHaveLength(1);
});
it("does not retry a timeout",async()=>{
 replies("Tijdslimiet bereikt: 300 seconden geen antwoord of geen volledig antwoord binnen 3600 seconden.",ok);
 await expect(modelRequest(remote,trace(),{total:3600,idle:300})).rejects.toThrow("timeout");
 expect(sends()).toHaveLength(1);
});
it("does not retry when too little time is left",async()=>{
 replies(lost,ok);
 await expect(modelRequest(remote,trace(),{total:2})).rejects.toBe(lost);
 expect(sends()).toHaveLength(1);
});
it("stops during the reconnect wait when cancelled",async()=>{
 const abort=new AbortController();
 replies(lost,ok);
 const pending=modelRequest(remote,trace(abort.signal));
 const settled=expect(pending).rejects.toMatchObject({name:"AbortError"});
 await vi.waitFor(()=>expect(logRetry).toHaveBeenCalled());
 abort.abort();
 await settled;
 expect(sends()).toHaveLength(1);
});
