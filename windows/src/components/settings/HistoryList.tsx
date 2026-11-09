// Earlier versions of one person or glossary entry, newest first, each with a "Herstel"
// button. The caller performs the restore; the list reloads afterwards.
import { useEffect, useState } from "react";
import { historyDate, versions, type HistoryEntry, type HistoryKind } from "../../services/contextHistory";

export function sourceText(source: string): string {
  if (source.startsWith("gesprek:")) return "Uit gesprek";
  if (source.startsWith("voorstel:")) return "Voorstel";
  return source === "herstel" ? "Hersteld" : "Handmatig";
}

export function HistoryList({ kind, itemId, onRestore, disabled = false }: {
  kind: HistoryKind;
  itemId: string;
  onRestore: (entry: HistoryEntry) => Promise<void>;
  disabled?: boolean;
}) {
  const [list, setList] = useState<HistoryEntry[]>([]);
  const reload = () => versions(kind, itemId).then(setList);
  useEffect(() => { void reload(); }, [kind, itemId]);
  if (!list.length) return <p className="history-empty">Nog geen eerdere versies</p>;
  return <ul className="history-list">
    {list.map(entry => <li key={entry.id}>
      <span>
        {historyDate(entry).toLocaleString("nl-NL", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })}
        <small>{sourceText(entry.source)}</small>
      </span>
      <button className="btn btn-secondary btn-sm" disabled={disabled} onClick={() => void onRestore(entry).then(reload)}>Herstel</button>
    </li>)}
  </ul>;
}
