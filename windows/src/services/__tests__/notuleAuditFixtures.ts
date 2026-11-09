// Explicit model audit fixtures; these do not assert that a real model is truthful.
export function auditFixture(user: string, status: string = "supported") {
  if (user.startsWith("Broncontrole")) return sourceFixture(user);
  const input = JSON.parse(user.split("\n").slice(1).join("\n")) as { source: { id: string }[]; notes: { id: string }[] };
  return JSON.stringify({
    source: input.source.map(s => ({ id: s.id, status: "covered" })),
    notes: input.notes.map(n => ({ id: n.id, status, evidence: input.source.map(s => s.id) })),
    uncertain: false,
  });
}

export function sourceFixture(_user: string) {
  return '{"uncertain":false}';
}
