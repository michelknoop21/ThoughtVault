import Foundation
@main struct Checks {
 static func main() throws {
  let rule = PersonalCorrection(id: "yinga", canonical: "Yinga", variants: ["Django", "Jengo"])
  assert(PersonalCorrections.text("DJANGO, Jengo Djangoes https://x.nl/Django Django@x.nl `Django`", entries:[rule],profileId:nil) == "Yinga, Yinga Djangoes https://x.nl/Django Django@x.nl `Django`")
  let source = "<style>.Django{}</style><!-- Django --><p title=\"Django > x\">Django</p><a href=\"/Django\">Django</a><pre><code>Django</code></pre><script>Django</script><p>Jengo</p>"
  assert(PersonalCorrections.html(source, entries:[rule],profileId:nil) == source.replacingOccurrences(of:">Django</p>",with:">Yinga</p>").replacingOccurrences(of:">Jengo</p>",with:">Yinga</p>"))
  let scoped = PersonalCorrection(id:"profile",canonical:"Yinga",variants:["Django"],scope:"meeting")
  assert(PersonalCorrections.text("Django",entries:[scoped],profileId:"tech") == "Django")
  assert(PersonalCorrections.text("Django",entries:[scoped],profileId:"meeting") == "Yinga")
  let multi = PersonalCorrection(canonical:"Ján de Vries",variants:["Jan de Vries","Jan"])
  assert(PersonalCorrections.text("Jan de Vries en Jan",entries:[multi],profileId:nil) == "Ján de Vries en Ján de Vries")
  let cascade = PersonalCorrection(canonical:"Other",variants:["Yinga"])
  assert(PersonalCorrections.text("Jengo",entries:[rule,cascade],profileId:nil) == "Yinga")
  let merged = PersonalCorrections.upsert([rule], entry:PersonalCorrection(canonical:"Yinga",variants:["Jingo"]))
  assert(merged.count == 1 && merged[0].id == rule.id && merged[0].variants == ["Django","Jengo","Jingo"])
  let encoded = try JSONEncoder().encode(CorrectionDocument(entries:[rule]))
  let object = try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
  assert(((object["entries"] as! [[String:Any]])[0]["scope"]) is NSNull)
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("list.json")
  defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
  try PersonalCorrections.save([rule],to:path)
  let restored = try PersonalCorrections.load(from:path); assert(restored == [rule])
  do { try PersonalCorrections.save([rule,scoped],to:path); assertionFailure("Conflict accepted") } catch {}
  let preserved = try PersonalCorrections.load(from:path); assert(preserved == [rule])
  print("PASS: Swift correction, markup, scope, Unicode, non-cascade and atomic persistence checks")
 }
}
