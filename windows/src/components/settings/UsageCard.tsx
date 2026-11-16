import { useSettingsStore } from "../../stores/settingsStore";
import { formatEuro, monthKey } from "../../services/usageMeter";
import type { MonthUsage } from "../../types";

const nl = (value: number) => value.toLocaleString("nl-NL");

function monthLine(month: MonthUsage): string {
  return `${nl(month.notules)} ${month.notules === 1 ? "notule" : "notules"} · ${nl(month.requests)} verzoeken · ${formatEuro(month.cost_usd)}`;
}

/** Usage of this month, counted on this pc only. */
export function UsageCard() {
  const ledger = useSettingsStore(state => state.usage_ledger) ?? {};
  const now = new Date();
  const previous = ledger[monthKey(new Date(now.getFullYear(), now.getMonth() - 1, 1))];
  const month = ledger[monthKey(now)] ?? { notules: 0, requests: 0, cost_usd: 0, unknown_cost_runs: 0 };
  return <section className="northstar-card"><h3>Gebruik deze maand</h3>
    <p>{monthLine(month)}</p>
    {month.unknown_cost_runs > 0 && <p>Van {nl(month.unknown_cost_runs)} {month.unknown_cost_runs === 1 ? "verwerking" : "verwerkingen"} zijn de kosten niet bekend; het bedrag is dus een ondergrens.</p>}
    <p>Geteld op deze pc.</p>
    {previous && <p>Vorige maand: {monthLine(previous)}</p>}
    <p>De kosten zitten vooral in de controle: die toetst elke zin van de notule apart aan het gesprek.</p>
  </section>;
}
