import { expect, it } from "vitest";
import { correctText, correctHTML, upsertCorrection, validateCorrections, correctionPrompt, type PersonalCorrection } from "../personalCorrections";
const rule: PersonalCorrection = { id:"yinga",canonical:"Yinga",variants:["Jengo","Django"],scope:null,enabled:true };
it("corrects exact Unicode words, loud/case variants and longest names without cascading", () => {
  expect(correctText("DJANGO, Jengo en Djangoes https://x.nl/Django Django@x.nl `Django`",[rule])).toBe("Yinga, Yinga en Djangoes https://x.nl/Django Django@x.nl `Django`");
  expect(correctText("Jan de Vries en Jan",[{...rule,canonical:"Ján de Vries",variants:["Jan de Vries","Jan"]}])).toBe("Ján de Vries en Ján de Vries");
  expect(correctText("Jengo",[rule,{...rule,id:"2",canonical:"Other",variants:["Yinga"]}])).toBe("Yinga");
});
it("keeps markup, attributes, links, code, CSS and comments intact", () => {
  const input = '<style>.Django{}</style><!-- Django --><p title="Django > x">Django</p><a href="/Django">Django</a><pre><code>Django</code></pre><script>Django</script><p>Jengo</p>';
  expect(correctHTML(input,[rule])).toBe(input.replace('>Django</p>','>Yinga</p>').replace('>Jengo</p>','>Yinga</p>'));
  expect(correctHTML('<p>Jengo</p>',[{...rule,canonical:"Yinga & Co"}])).toBe('<p>Yinga &amp; Co</p>');
});
it("uses only enabled rules in the matching profile", () => {
  const scoped = {...rule,scope:"meeting"};
  expect(correctText("Django",[scoped],"tech")).toBe("Django");
  expect(correctText("Django",[scoped],"meeting")).toBe("Yinga");
  expect(correctionPrompt([scoped],"tech")).toBe("");
  expect(correctText("Django",[{...rule,enabled:false}])).toBe("Django");
});
it("rejects conflicts, invalid documents and identical or empty variants", () => {
  expect(()=>validateCorrections({version:1,entries:[rule,{...rule,id:"2",scope:"meeting"}]})).toThrow("regel");
  expect(()=>validateCorrections({version:1,entries:[{...rule,variants:[" "]}]})).toThrow();
  expect(()=>validateCorrections({version:1,entries:[{...rule,variants:["Yinga"]}]})).toThrow();
  expect(()=>validateCorrections({version:1,entries:[{...rule,scope:"a"},{...rule,id:"2",scope:"b"}]})).not.toThrow();
});

it("merges new approved variants into an existing term without losing its identity", () => {
  const entries = upsertCorrection([rule], {...rule,id:"new",variants:["Jingo","django"]});
  expect(entries).toEqual([{...rule,variants:["Jengo","django","Jingo"]}]);
  expect(()=>validateCorrections({version:1,entries})).not.toThrow();
});
